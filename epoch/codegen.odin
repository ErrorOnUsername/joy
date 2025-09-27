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
	build_dominator_tree(fn, start, bm) or_return

	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	schedule_global_early(fn, bm, &visited) or_return

	final_global_schedule(fn, bm, &visited) or_return

	local_schedule(fn, &visited) or_return

	return true
}

// Schedules all the floating nodes as soon as their inputs allow
schedule_global_early :: proc(fn: ^Function, bm: ^BlockMap, visited: ^Worklist) -> bool {
	// dedup
	stack_pop :: proc(a: ^[dynamic]^Node) -> ^Node {
		if len(a) == 0 do return nil
		return pop(a)
	}
	get_start :: proc(n: ^Node) -> ^Node {
		s := n
		for !is_bb_start(s) {
			next := s.inputs[0]
			if next == nil do break
			s = next
		}
		return s
	}

	stack: [dynamic]^Node
	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]
		assert(n != nil)

		worklist_push(visited, n)

		unpinned_input := false
		for input in n.inputs {
			if !is_node_pinned(input) {
				assert(!worklist_contains(visited, input)) // should only happen for control back-edges (loops)
				append(&stack, input)
				unpinned_input = true
			}
		}

		// DFS
		if unpinned_input do continue

		// This ones ready to schedule (all inputs pinned already)

		deepest_input_bb: ^BasicBlock
		for input in n.inputs {
			input_ctrl_node := input.inputs[0] // maybe make a helper since this is kinda ugly :(
			assert(input_ctrl_node != nil) // ruhroh rhaggy
			// This can go away if we map the pinned nodes before this bs since they won't change anyways
			input_ctrl_node = get_start(input_ctrl_node)
			assert(is_bb_start(input_ctrl_node))
			input_bb := block_map_get_node_block(bm, input_ctrl_node)
			assert(input_bb != nil)
			if deepest_input_bb == nil || input_bb.dom_depth > deepest_input_bb.dom_depth {
				deepest_input_bb = input_bb
			}
		}

		n.inputs[0] = deepest_input_bb.nodes[0]

		stack_pop(&stack)
	}

	return true
}

// Picks the final location for the nodes (as late as possible while also pulling code out of loops as much as it can)
final_global_schedule :: proc(fn: ^Function, bm: ^BlockMap, visited: ^Worklist) -> bool {
	stack_pop :: proc(a: ^[dynamic]^Node) -> ^Node {
		if len(a) == 0 do return nil
		return pop(a)
	}
	get_start :: proc(n: ^Node) -> ^Node {
		s := n
		for !is_bb_start(s) {
			next := s.inputs[0]
			if next == nil do break
			s = next
		}
		return s
	}

	stack: [dynamic]^Node
	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]
		assert(n != nil)

		worklist_push(visited, n)

		unhandled_input := false
		for input in n.inputs {
			if !worklist_contains(visited, input) {
				// start nodes don't have inputs but we still want to add them ig. not super important
				assert(input.kind == .Start || is_node_pinned(input))
				append(&stack, input)
				unhandled_input = true
			}
		}

		if unhandled_input do continue

		if block_map_get_node_block(bm, n) == nil && n.kind != .End { // These can be moved since they aren't required to stay here like calls, volatile stores, jmps, etc you get it
			// place the node before the first use and hoist out of loops where needed
			pin_point := n.inputs[0]
			assert(is_bb_start(pin_point))
			pin_bb := block_map_get_node_block(bm, pin_point)
			highest_use: ^BasicBlock
			for u in n.users {
				u_ctrl := u.n.inputs[0]
				assert(u_ctrl != nil)
				u_ctrl = get_start(u_ctrl)
				u_bb := block_map_get_node_block(bm, u_ctrl)
				assert(u_bb != nil)
				if highest_use == nil || u_bb.dom_depth < highest_use.dom_depth {
					highest_use = u_bb
				}
			}

			assert(highest_use != nil)

			final_bb := highest_use
			// FIXME: Implement loop_nest tracking (ie actually write the code for the loop tree dumbass)
			for final_bb != pin_bb && final_bb.loop_nest > 0 {
				final_bb = final_bb.dom
			}

			n.inputs[0] = final_bb.nodes[0]
		}

		stack_pop(&stack)
	}

	return true
}

local_schedule :: proc(fn: ^Function, visited: ^Worklist) -> bool {
	return true
}

// There's probably a goofy ass paper out there that has this same solution idk i just wrote the sombitch from first principles
build_dominator_tree :: proc(fn: ^Function, start: ^BasicBlock, bm: ^BlockMap) -> bool {
	assert(fn != nil)
	assert(start != nil)
	assert(bm != nil)

	blocks: [dynamic]^Node // this is kinda stupid just build a list in the first place lol
	defer delete(blocks)

	append(&blocks, start.nodes[0])
	block_number := 1

	get_start :: proc(n: ^Node) -> ^Node {
		s := n
		for !is_bb_start(s) {
			next := s.inputs[0]
			if next == nil do break
			s = next
		}
		return s
	}

	get_pred :: proc(n: ^Node) -> ^Node {
		if len(n.inputs) == 0 do return nil
		return get_start(n.inputs[0])
	}

	walk_up_to_find :: proc(from: ^Node, to: ^Node) -> bool {
		curr := from
		for curr != nil {
			assert(is_bb_start(curr))
			if curr == to {
				return true
			}
			curr = get_pred(curr)
		}
		return false
	}

	get_common_pred :: proc(a: ^Node, b: ^Node) -> ^Node {
		x := a
		y := b
		for x != y {
			if walk_up_to_find(x, y) {
				return y
			}
			if walk_up_to_find(y, x) {
				return x
			}

			x = get_pred(x)
			y = get_pred(y)
		}
		return nil
	}

	for {
		did_work := false
		for x in blocks {
			bb := block_map_get_node_block(bm, x)
			assert(bb != nil)

			if bb.id != 0 {
				// already checked this one (loop back-edge)
				continue
			}

			did_work = true

			bb.id = block_number
			block_number += 1

			highest := x // sentinel state for the start node since it has no inputs
			for input in x.inputs { // This won't work when we change the inputs
				start := get_start(input)
				highest = get_common_pred(highest, start)
			}
			highest_bb := block_map_get_node_block(bm, highest)
			assert(highest_bb != nil)
			bb.dom = highest_bb

			// copy bookkeeping state so that child blocks makes sense
			bb.dom_depth = highest_bb.dom_depth + 1

			for s in bb.succ {
				append(&blocks, s)
			}
		}
		if !did_work {
			break
		}
	}

	return true
}

register_allocate :: proc(fn: ^Function, start: ^BasicBlock) -> bool {
	return true
}

write_machine_code :: proc(fn: ^Function, start: ^BasicBlock) -> ([]u8, bool) {
	return {}, true
}

