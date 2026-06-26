package opto


impl_aarch64 := ArchImpl {
	reg_names = {},
	abi = {
	},
	select = aarch64_select,
	encode = aarch64_encode,
	encoding_size = aarch64_encoding_size,
	patch_local_relo = aarch64_patch_local_relo,
	get_callee_save_regmask = aarch64_get_callee_save_regmask,
	get_src_regmask = aarch64_get_src_regmask,
	get_dst_regmask = aarch64_get_dst_regmask,
	get_kill_regmask = aarch64_get_kill_regmask,
	is_two_address_op = aarch64_is_two_address_op,
	get_two_address_index = aarch64_get_two_address_index,
}

aarch64_select :: proc(fn: ^Function, n: ^Node) -> MachineOp {
	panic("impl select")
}

aarch64_encode :: proc(fn: ^Function, n: ^Node, bm: ^BlockMap) -> bool {
	panic("impl encode")
}

aarch64_encoding_size :: proc(n: ^Node, delta_from_start_to_target: int) -> int {
	panic("impl encoding size")
}

aarch64_patch_local_relo :: proc(fn: ^Function, n: ^Node, start: int, delta_from_start_to_target: int) {
	panic("impl patch_local_relo")
}

aarch64_get_callee_save_regmask ::  proc(ctx: ^RegAllocContext) -> RegisterMask {
	panic("impl get_calle_save_regmask")
}

aarch64_get_src_regmask :: proc(ctx: ^RegAllocContext, n: ^Node, from: int) -> RegisterMask {
	panic("impl get_src_regmask")
}

aarch64_get_dst_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	panic("impl get_dst_regmask")
}

aarch64_get_kill_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	panic("impl get_kill_regmask")
}

aarch64_is_two_address_op :: proc(ctx: ^RegAllocContext, n: ^Node) -> bool {
	panic("impl is_two_address_op")
}

aarch64_get_two_address_index :: proc(ctx: ^RegAllocContext, n: ^Node) -> int {
	panic("impl get_two_address_index")
}
