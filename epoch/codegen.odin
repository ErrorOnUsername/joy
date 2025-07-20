package epoch


BasicBlock :: struct {
	members: [dynamic]^Node,
	from: []BasicBlock,
	to: []BasicBlock,
}

DominatorTreeNode :: struct {
	block: ^BasicBlock,
}

codegen_function :: proc(ctx: ^EpochContext, fn: ^Function) -> bool {
	start := build_cfg(ctx, fn) or_return

	perform_code_motion(ctx, fn, start) or_return

	return true
}

build_cfg :: proc(ctx: ^EpochContext, fn: ^Function) -> (^BasicBlock, bool) {
	return nil, false
}

perform_code_motion :: proc(ctx: ^EpochContext, fn: ^Function, start: ^BasicBlock) -> bool {
	build_dominator_tree(fn, start) or_return
	return true
}

build_dominator_tree :: proc(fn: ^Function, start: ^BasicBlock) -> (^DominatorTreeNode, bool) {
	return nil, false
}

