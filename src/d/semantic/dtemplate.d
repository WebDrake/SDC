module d.semantic.dtemplate;

import d.semantic.base;
import d.semantic.identifiable;
import d.semantic.semantic;

import d.ast.declaration;
import d.ast.dscope;
import d.ast.dtemplate;
import d.ast.expression;
import d.ast.type;

import sdc.location;

import std.algorithm;
import std.array;

final class TemplateInstancier {
	private SemanticPass pass;
	alias pass this;
	
	this(SemanticPass pass) {
		this.pass = pass;
	}
	
	auto instanciate(Location location, TemplateDeclaration tplDecl, TemplateArgument[] arguments) {
		tplDecl = cast(TemplateDeclaration) scheduler.require(tplDecl);
		
		Declaration[] argDecls;
		uint i = 0;
		
		// XXX: have to put array once again.
		assert(tplDecl.parameters.length == arguments.length);
		string id = arguments.map!(delegate string(TemplateArgument arg) {
			auto identifiable = visit(arg);
			
			if(auto type = identifiable.asType()) {
				argDecls ~= new AliasDeclaration(arg.location, tplDecl.parameters[i++].name, type);
				
				return "T" ~ pass.typeMangler.visit(type);
			}
			
			assert(0, "Only type argument are supported.");
		}).array().join();
		
		return tplDecl.instances.get(id, {
			auto oldManglePrefix = this.manglePrefix;
			scope(exit) this.manglePrefix = oldManglePrefix;
			
			import std.conv;
			auto tplMangle = "__T" ~ to!string(tplDecl.name.length) ~ tplDecl.name ~ id ~ "Z";
			
			this.manglePrefix = tplDecl.mangle ~ to!string(tplMangle.length) ~ tplMangle;
			
			import d.semantic.clone;
			auto clone = new ClonePass();
			auto members = tplDecl.declarations.map!(delegate Declaration(Declaration d) { return clone.visit(d); }).array();
			
			auto instance = new TemplateInstance(location, arguments, argDecls ~ members);
			
			// Update scope.
			auto oldScope = pass.currentScope;
			scope(exit) pass.currentScope = oldScope;
			
			pass.currentScope = instance.dscope = new NestedScope(oldScope);
			
			auto syms = cast(Symbol[]) pass.visit(instance.declarations);
			
			instance.declarations = cast(Declaration[]) pass.scheduler.require(syms);
			
			return tplDecl.instances[id] = instance;
		}());
	}
	
	Identifiable visit(TemplateArgument arg) {
		return this.dispatch(arg);
	}
	
	Identifiable visit(TypeTemplateArgument arg) {
		return Identifiable(pass.visit(arg.type));
	}
	
	Identifiable visit(AmbiguousTemplateArgument arg) {
		if(auto type = pass.visit(arg.argument.type)) {
			return Identifiable(type);
		} else if(auto expression = pass.visit(arg.argument.expression)) {
			return Identifiable(expression);
		}
		
		assert(0, "Ambiguous can't be deambiguated.");
	}
}
