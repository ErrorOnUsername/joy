package epoch


BasicBlock :: struct {
	nodes:  [dynamic]^Node,
	succ:   []^Node,
}

DominatorTreeNode :: struct {
	block: ^BasicBlock,
}

codegen_function :: proc(ctx: ^EpochContext, fn: ^Function) -> bool {
	// TODO: insr selection

	start := build_cfg(ctx, fn) or_return

	perform_code_motion(ctx, fn, start) or_return

	register_allocate(fn, start) or_return

	buf := write_machine_code(fn, start) or_return

	return true
}

build_cfg :: proc(ctx: ^EpochContext, fn: ^Function) -> (^BasicBlock, bool) {
	wl: Worklist
	worklist_init(&wl, fn.node_count, fn.allocator)
	defer worklist_deinit(&wl)

	start: ^BasicBlock

	worklist_push(&wl, fn.start)
	for x := worklist_pop(&wl); x != nil; x = worklist_pop(&wl) {
		assert(is_bb_start(x))
		end := get_bb_terminator_from(x)
		assert(is_bb_term(end))

		bb := new(BasicBlock, fn.allocator)
		append(&bb.nodes, x)
		append(&bb.nodes, end)

		if end.kind == .Branch {
			bb.succ = make([]^Node, 2, fn.allocator)

			bb.succ[0] = end.inputs[2] // true branch
			bb.succ[1] = end.inputs[3] // false branch
		} else if end.kind == .Goto {
			bb.succ = make([]^Node, 1, fn.allocator)
			bb.succ[0] = end.inputs[1]
		}

		for s in bb.succ {
			worklist_push(&wl, s)
		}

		if x.kind == .Start {
			start = bb
		}
	}

	return start, true
}

is_bb_start :: proc(n: ^Node) -> bool {
	if n == nil do return false

	#partial switch n.kind {
		case .Region, .Start: return true
	}

	return false
}

is_bb_term :: proc(n: ^Node) -> bool {
	if n == nil do return false

	#partial switch n.kind {
		case .Goto, .Branch, .Return: return true
	}

	return false
}

is_control_proj :: proc(n: ^Node) -> bool {
	return n.kind == .Proj && ty_is_ctrl(n.type)
}

is_ctrl_node :: proc(n: ^Node) -> bool {
	if ty_is_ctrl(n.type) do return true
	if ty_is_tuple(n.type) {
		for u in &n.users {
			if is_control_proj(u.n) {
				return true
			}
		}
	}
	return false
}

get_next_control :: proc(n: ^Node) -> ^Node {
	for u in &n.users {
		if is_ctrl_node(u.n) && u.slot == 0 && !is_bb_start(u.n) {
			return u.n
		}
	}
	return nil
}

get_bb_terminator_from :: proc(n: ^Node) -> ^Node {
	x := n
	for !is_bb_term(x) {
		next := get_next_control(x)
		assert(!is_bb_start(next))
		if next == nil {
			break
		}
		x = next
	}
	return x
}

perform_code_motion :: proc(ctx: ^EpochContext, fn: ^Function, start: ^BasicBlock) -> bool {
	root := build_dominator_tree(fn, start) or_return
	return true
}

build_dominator_tree :: proc(fn: ^Function, start: ^BasicBlock) -> (^DominatorTreeNode, bool) {
	return nil, true
}

register_allocate :: proc(fn: ^Function, start: ^BasicBlock) -> bool {
	return true
}

write_machine_code :: proc(fn: ^Function, start: ^BasicBlock) -> ([]u8, bool) {
	return {}, true
}

