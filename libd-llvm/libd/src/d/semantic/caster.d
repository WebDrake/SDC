module d.semantic.caster;

import d.semantic.semantic;
import d.semantic.typepromotion;

import d.ast.adt;
import d.ast.declaration;
import d.ast.dfunction;
import d.ast.expression;
import d.ast.type;

import d.exception;
import d.location;

enum CastFlavor {
	Not,
	Bool,
	Trunc,
	Pad,
	Bit,
	Exact,
}

// FIXME: isn't reentrant at all.
final class Caster(bool isExplicit) {
	private SemanticPass pass;
	alias pass this;
	
	private Location location;
	
	private FromBoolean fromBoolean;
	private FromInteger fromInteger;
	private FromCharacter fromCharacter;
	private FromPointer fromPointer;
	private FromFunction fromFunction;
	
	this(SemanticPass pass) {
		this.pass = pass;
		
		fromBoolean		= new FromBoolean();
		fromInteger		= new FromInteger();
		// fromFloat		= new FromFloat();
		fromCharacter	= new FromCharacter();
		fromPointer		= new FromPointer();
		fromFunction	= new FromFunction();
	}
	
	// XXX: out contract disabled because it create memory corruption with dmd.
	Expression build(Location castLocation, Type to, Expression e) /* out(result) {
		assert(result.type == to);
	} body */ {
		/*
		import sdc.terminal;
		outputCaretDiagnostics(e.location, "Cast " ~ typeid(e).toString() ~ " to " ~ typeid(to).toString());
		//*/
		
		// If the expression is polysemous, we try the several meaning and exclude the ones that make no sense.
		if(auto asPolysemous = cast(PolysemousExpression) e) {
			auto oldBuildErrorNode = buildErrorNode;
			scope(exit) buildErrorNode = oldBuildErrorNode;
			
			buildErrorNode = true;
			
			Expression casted;
			foreach(candidate; asPolysemous.expressions) {
				try {
					candidate = build(castLocation, to, candidate);
				} catch(CompileException e) {
					continue;
				}
				
				if(cast(ErrorExpression) candidate) {
					continue;
				}
				
				if(casted) {
					return pass.raiseCondition!Expression(e.location, "Ambiguous.");
				}
				
				casted = candidate;
			}
			
			if(casted) {
				return casted;
			}
			
			return pass.raiseCondition!Expression(e.location, "No match found.");
		}
		
		assert(to && e.type);
		
		// Default initializer removal.
		if(typeid(e) is typeid(DefaultInitializer)) {
			return defaultInitializerVisitor.visit(e.location, to);
		}
		
		auto oldLocation = location;
		scope(exit) location = oldLocation;
		
		location = castLocation;
		
		final switch(castFrom(e.type, to)) with(CastFlavor) {
			case Not :
				return pass.raiseCondition!Expression(e.location, (isExplicit?"Explicit":"Implicit") ~ " cast from " ~ e.type.toString() ~ " to " ~ to.toString() ~ " is not allowed");
			
			case Bool :
				Expression zero = makeLiteral(castLocation, 0);
				auto type = getPromotedType(castLocation, e.type, zero.type);
				
				zero = pass.implicitCast(castLocation, type, zero);
				e = pass.implicitCast(e.location, type, e);
				
				auto res = new NotEqualityExpression(castLocation, e, zero);
				res.type = to;
				
				return res;
			
			case Trunc :
				return new TruncateExpression(location, to, e);
			
			case Pad :
				return new PadExpression(location, to, e);
			
			case Bit :
				return new BitCastExpression(location, to, e);
			
			case Exact :
				return e;
		}
	}
	
	CastFlavor castFrom(Type from, Type to) {
		if(from == to) {
			return CastFlavor.Exact;
		}
		
		return this.dispatch!((t) {
			throw new CompileException(location, typeid(t).toString() ~ " is not supported");
		})(to, from);
	}
	
	class FromBoolean {
		CastFlavor visit(Type to) {
			return this.dispatch!((t) {
				throw new CompileException(location, typeid(t).toString() ~ " is not supported");
			})(to);
		}
		
		CastFlavor visit(IntegerType to) {
			return CastFlavor.Pad;
		}
	}
	
	CastFlavor visit(Type to, BooleanType t) {
		return fromBoolean.visit(to);
	}
	
	class FromInteger {
		Integer from;
		
		CastFlavor visit(Integer from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				throw new CompileException(location, typeid(t).toString() ~ " is not supported");
			})(to);
		}
		
		static if(isExplicit) {
			CastFlavor visit(BooleanType t) {
				return CastFlavor.Bool;
			}
			
			CastFlavor visit(EnumType t) {
				// If the cast is explicit, then try to cast from enum base type.
				return visit(from, t.type);
			}
		}
		
		CastFlavor visit(IntegerType t) {
			if(t.type >> 1 == from >> 1) {
				// Same type except for signess.
				return CastFlavor.Bit;
			} else if(t.type > from) {
				return CastFlavor.Pad;
			} else static if(isExplicit) {
				return CastFlavor.Trunc;
			} else {
				return CastFlavor.Not;
			}
		}
	}
	
	CastFlavor visit(Type to, IntegerType t) {
		return fromInteger.visit(t.type, to);
	}
	
	/*
	CastFlavor visit(FloatType t) {
		return fromFloatType(t.type)).visit(type);
	}
	*/
	
	class FromCharacter {
		Character from;
		
		CastFlavor visit(Character from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				throw new CompileException(location, typeid(t).toString() ~ " is not supported");
			})(to);
		}
		
		CastFlavor visit(IntegerType t) {
			Integer i;
			final switch(from) {
				case Character.Char :
					i = Integer.Ubyte;
					break;
				
				case Character.Wchar :
					i = Integer.Ushort;
					break;
				
				case Character.Dchar :
					i = Integer.Uint;
					break;
			}
			
			return fromInteger.visit(i, t);
		}
		
		CastFlavor visit(CharacterType t) {
			if(t.type == from) {
				return CastFlavor.Bit;
			}
			
			return CastFlavor.Not;
		}
	}
	
	CastFlavor visit(Type to, CharacterType t) {
		return fromCharacter.visit(t.type, to);
	}
	
	class FromPointer {
		Type from;
		
		CastFlavor visit(Type from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				throw new CompileException(location, typeid(t).toString() ~ " is not supported");
			})(to);
		}
		
		CastFlavor visit(PointerType t) {
			static if(isExplicit) {
				return CastFlavor.Bit;
			} else if(auto toType = cast(VoidType) t.type) {
				return CastFlavor.Bit;
			} else {
				// Ugly hack :D
				auto subCast = castFrom(from, t.type);
				
				// If subCast is a bitcast or an exact match, then it is safe to cast pointers.
				if(subCast >= CastFlavor.Bit) {
					static if(isExplicit) {
						return CastFlavor.Bit;
					} else {
						return canConvert(from.qualifier, t.type.qualifier) ? CastFlavor.Bit : CastFlavor.Not;
					}
				}
				
				return CastFlavor.Not;
			}
		}
		
		static if(isExplicit) {
			CastFlavor visit(FunctionType t) {
				return CastFlavor.Bit;
			}
		}
	}
	
	CastFlavor visit(Type to, PointerType t) {
		return fromPointer.visit(t.type, to);
	}
	
	class FromFunction {
		FunctionType from;
		
		CastFlavor visit(FunctionType from, Type to) {
			auto oldFrom = this.from;
			scope(exit) this.from = oldFrom;
			
			this.from = from;
			
			return this.dispatch!((t) {
				throw new CompileException(location, typeid(t).toString() ~ " is not supported");
			})(to);
		}
		
		CastFlavor visit(PointerType t) {
			static if(isExplicit) {
				return CastFlavor.Bit;
			} else if(auto toType = cast(VoidType) t.type) {
				return CastFlavor.Bit;
			} else {
				return CastFlavor.Not;
			}
		}
	}
	
	CastFlavor visit(Type to, FunctionType t) {
		return fromFunction.visit(t, to);
	}
	
	CastFlavor visit(Type to, EnumType t) {
		// Automagically promote to base type.
		return castFrom(t.type, to);
	}
}

