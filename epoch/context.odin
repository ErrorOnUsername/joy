package epoch

import "core:mem"
import "core:sync"


ListEntry :: struct ($T: typeid) {
	el: T,
	next: ^ListEntry(T)
}

Module :: struct {
	name: string,
	pool: mem.Dynamic_Pool,
	allocator: mem.Allocator,
	symbols: ^ListEntry(Symbol),
}

EpochContext :: struct {
	global_alloc_lock: sync.Mutex,
	pool: mem.Dynamic_Pool,
	global_allocator: mem.Allocator,
	modules: ^ListEntry(Module),
}

context_init :: proc(ctx: ^EpochContext) {
	mem.dynamic_pool_init(&ctx.pool)
	ctx.global_allocator = mem.dynamic_pool_allocator(&ctx.pool)
}

module_list_get_tail :: proc(head: ^ListEntry(Module)) -> ^ListEntry(Module) {
	if head != nil && head.next != nil {
		return module_list_get_tail(head.next)
	}
	return head
}

create_module :: proc(ctx: ^EpochContext, name: string) -> ^Module {
	mod := new(ListEntry(Module), ctx.global_allocator)
	mod.el.name = name
	mem.dynamic_pool_init(&mod.el.pool)
	mod.el.allocator = mem.dynamic_pool_allocator(&mod.el.pool)

	tail := module_list_get_tail(ctx.modules)

	if tail == nil {
		ctx.modules = mod
	} else {
		tail.next = mod
	}

	return &mod.el
}
