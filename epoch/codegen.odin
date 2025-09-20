package epoch

import "core:fmt"


codegen_function :: proc(ctx: ^EpochContext, fn: ^Function) -> bool {
	// TODO: insr selection

	block_map := block_map_create(fn)
	defer block_map_destroy(&block_map)

	start := build_cfg(ctx, fn, &block_map) or_return

	perform_code_motion(ctx, fn, start, &block_map) or_return

	register_allocate(fn, start) or_return

	buf := write_machine_code(fn, start) or_return

	return true
}

build_cfg :: proc(ctx: ^EpochContext, fn: ^Function, bm: ^BlockMap) -> (^BasicBlock, bool) {
	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	start: ^BasicBlock

	stack: [dynamic]^Node
	defer delete(stack)

	stack_pop :: proc(a: ^[dynamic]^Node) -> ^Node {
		if len(a) == 0 do return nil
		return pop(a)
	}

	append(&stack, fn.start)
	for x := stack_pop(&stack); x != nil; x = stack_pop(&stack) {
		if worklist_contains(&visited, x) do continue
		worklist_push(&visited, x)

		assert(is_bb_start(x))
		end := get_bb_terminator_from(x)
		assert(is_bb_term(end))

		bb := new(BasicBlock, fn.allocator)
		append(&bb.nodes, x)
		block_map_set_node_block(bm, x, bb)
		append(&bb.nodes, end)
		block_map_set_node_block(bm, end, bb)

		if end.kind == .Branch {
			bb.succ = make([]^Node, 2, fn.allocator)

			bb.succ[0] = end.inputs[2] // true branch
			bb.succ[1] = end.inputs[3] // false branch
		} else if end.kind == .Goto {
			bb.succ = make([]^Node, 1, fn.allocator)
			bb.succ[0] = end.inputs[1]
		}

		for s in bb.succ {
			append(&stack, s)
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

perform_code_motion :: proc(ctx: ^EpochContext, fn: ^Function, start: ^BasicBlock, bm: ^BlockMap) -> bool {
	root := build_dominator_tree(fn, start, bm) or_return
	return true
}


DominatorTreeNode :: struct {
	block: ^BasicBlock,
	idom: ^DominatorTreeNode, // immediate dominator
}

build_dominator_tree :: proc(fn: ^Function, start: ^BasicBlock, bm: ^BlockMap) -> (^DominatorTreeNode, bool) {
	stack: [dynamic]^Node
	defer delete(stack)

	append(&stack, start.nodes[0])
	block_number := 1

	for len(stack) > 0 {
		start_node := pop(&stack)
		bb := block_map_get_node_block(bm, start_node)
		assert(bb != nil)

		if bb.id != 0 {
			continue // already checked this one (loop back-edge)
		}

		bb.id = block_number
		block_number += 1

		for s in bb.succ {
			append(&stack, s)
		}
	}

	return nil, true
}

register_allocate :: proc(fn: ^Function, start: ^BasicBlock) -> bool {
	return true
}

write_machine_code :: proc(fn: ^Function, start: ^BasicBlock) -> ([]u8, bool) {
	return {}, true
}

