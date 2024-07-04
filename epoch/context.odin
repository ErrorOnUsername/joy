package epoch

import "core:mem"
import "core:sync"


ListEntry :: struct ($T: typeid) {
	el: T,
	next: ^ListEntry(T)
}

Module :: struct {
	name: string,
	symbols: ^ListEntry(Symbol),
}

EpochContext :: struct {
	global_alloc_lock: sync.Mutex,
	global_allocator: mem.Allocator,
	modules: ^ListEntry(Module),
}

