module d.sync.atomic;

import sdc.intrinsics;

alias icas = cas;
alias casWeak = cas;
alias icasWeak = casWeak;

enum MemoryOrder {
	Relaxed,
	Consume,
	Acquire,
	Release,
	AcqRel,
	SeqCst,
}

struct Atomic(T) {
private:
	T val;
	
public:
	T load(MemoryOrder order = MemoryOrder.SeqCst) {
		return val;
	}
	
	void store(T val, MemoryOrder order = MemoryOrder.SeqCst) {
		this.val = val;
	}
	
	bool cas(T expected, T desired, MemoryOrder order = MemoryOrder.SeqCst) {
		auto cr = icas(&val, expected, desired);
		return cr.success;
	}
	
	bool casWeak(
		T expected,
		T desired,
		MemoryOrder order = MemoryOrder.SeqCst,
	) {
		auto cr = icasWeak(&val, expected, desired);
		return cr.success;
	}
}
