package opto

import "core:fmt"
import "core:strings"


codegen_function :: proc(ctx: ^OptoContext, fn: ^Function) -> bool {
	log(fn, "-- Begin CodeGen --")
	defer log(fn, "-- End CodeGen --")

	insr_select(fn) or_return

	block_map := block_map_create(fn)
	defer block_map_destroy(&block_map)

	blocks := build_cfg(ctx, fn, &block_map) or_return

	perform_code_motion(ctx, fn, blocks, &block_map) or_return

	register_allocate(fn, blocks, &block_map) or_return

	emit(fn, blocks) or_return

	return true
}

insr_select :: proc(fn: ^Function) -> bool {
	log(fn, "-- Begin ISel --")
	defer log(fn, "-- End ISel --")

	impl := arch_impl(.Amd64)

	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	stack: [dynamic]^Node
	defer delete(stack)

	append(&stack, fn.end)

	for len(stack) > 0 {
		x := stack[len(stack) - 1]

		worklist_push(&visited, x)

		unhandled_input := false
		for input in x.inputs {
			if input != nil && !worklist_contains(&visited, input) {
				unhandled_input = true
				append(&stack, input)
				break
			}
		}
		if unhandled_input do continue

		if is_selectable_node(x) {
			x.uop = impl.select(fn, x)
		}

		pop(&stack)
	}

	return true
}

is_selectable_node :: proc(n: ^Node) -> bool {
	#partial switch n.kind {
		case .Start, .End, .Region, .IntConst, .F32Const, .F64Const, .Symbol, .Phi:
			return false
	}
	return !(ty_is_ctrl(n.type) || ty_is_mem(n.type))
}

build_cfg :: proc(ctx: ^OptoContext, fn: ^Function, bm: ^BlockMap) -> (blocks: []^BasicBlock, ok: bool) {
	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	log(fn, "-- Begin CFG Build --")
	defer log(fn, "-- End CFG Build --")

	start: ^BasicBlock

	stack: [dynamic]^Node
	defer delete(stack)

	stack_pop :: proc(a: ^[dynamic]^Node) -> ^Node {
		if len(a) == 0 do return nil
		return pop(a)
	}

	blocks_map: map[string]^BasicBlock
	defer delete(blocks_map)

	append(&stack, fn.start)
	for x := stack_pop(&stack); x != nil; x = stack_pop(&stack) {
		if worklist_contains(&visited, x) do continue
		worklist_push(&visited, x)

		assert(is_bb_start(x))
		end := get_bb_terminator_from(x)
		assert(is_bb_term(end))

		block_name := x.extra.tag if x.extra != nil && len(x.extra.tag) > 0 else "nil"

		block_name_scratch: strings.Builder
		if block_name in blocks_map {
			block_idx := 1
			new_block_name := block_name
			for {
				new_block_name = fmt.sbprintf(&block_name_scratch, "{}.{}", block_name, block_idx)
				block_idx += 1
				if !(new_block_name in blocks_map) {
					break
				}
				strings.builder_reset(&block_name_scratch)
			}
			block_name = strings.clone(new_block_name)
		}
		strings.builder_destroy(&block_name_scratch)

		log(fn, "new block: {}", block_name)

		bb := new(BasicBlock, fn.allocator)
		bb.name = block_name
		append(&bb.nodes, x)
		block_map_set_node_block(bm, x, bb)
		append(&bb.nodes, end)
		block_map_set_node_block(bm, end, bb)

		blocks_map[block_name] = bb

		// Add all the pinned nodes (for scheduling purposes later on)
		walk := end
		for {
			assert(walk == x || walk.inputs[0] != nil)
			block_map_set_node_block(bm, walk, bb)
			for u in walk.users {
				if u.slot == 0 {
					block_map_set_node_block(bm, u.n, bb)
				}
			}
			if walk == x do break // We do this here instead of the loop condition so that we add the users of the start node
			walk = walk.inputs[0]
		}

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

	build_dominator_tree(fn, start, bm) or_return

	block_stack: [dynamic]^BasicBlock
	defer delete(block_stack)

	end := block_map_get_node_block(bm, fn.end.inputs[0])
	assert(end != nil)
	append(&block_stack, end)

	final_block_list := make([]^BasicBlock, len(blocks_map))
	final_index := 0
	for len(block_stack) > 0 {
		bb := block_stack[len(block_stack) - 1]
		bb_start := bb.nodes[0]

		if blocks_map[bb.name] != nil {
			blocks_map[bb.name] = nil
		}

		is_dominated_by :: proc(from: ^BasicBlock, to: ^BasicBlock) -> bool {
			curr := from
			for curr != curr.dom {
				if curr == to do break
				curr = curr.dom
			}
			return curr == to
		}

		// This sucks maybe just flag the block so this is fast
		is_block_scheduled :: proc(block_list: []^BasicBlock, bb: ^BasicBlock) -> bool {
			for block in block_list {
				if block == bb do return true
			}
			return false
		}

		is_loop_header := false
		loop_body_bb: ^BasicBlock
		is_body_done := false
		all_other_edges_done := true
		for input in bb_start.inputs {
			in_bb := block_map_get_node_block(bm, input)
			if is_dominated_by(in_bb, bb) {
				is_loop_header = true
				loop_body_bb = in_bb
				is_body_done = blocks_map[in_bb.name] == nil
			} else if !is_block_scheduled(final_block_list, in_bb) {
				all_other_edges_done = false
			}
		}

		if is_loop_header && all_other_edges_done && !is_body_done {
			final_block_list[final_index] = bb
			final_index += 1
		}

		unhandled_in := false
		for input in bb_start.inputs {
			in_bb := block_map_get_node_block(bm, input) // bb end nodes are still mapped so this will work
			if blocks_map[in_bb.name] != nil {
				unhandled_in = true
				append(&block_stack, in_bb)
				break
			}
		}
		if unhandled_in do continue

		if !is_loop_header {
			final_block_list[final_index] = bb
			final_index += 1
		}

		pop(&block_stack)
	}

	return final_block_list, true
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

perform_code_motion :: proc(ctx: ^OptoContext, fn: ^Function, blocks: []^BasicBlock, bm: ^BlockMap) -> bool {
	log(fn, "-- Begin Code Motion --")
	defer log(fn, "-- End Code Motion --")

	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	schedule_global_early(fn, bm, &visited) or_return

	worklist_clear(&visited)

	final_global_schedule(fn, bm, &visited) or_return

	worklist_clear(&visited)

	local_schedule(fn, blocks, bm, &visited) or_return

	return true
}

// Schedules all the floating nodes as soon as their inputs allow
schedule_global_early :: proc(fn: ^Function, bm: ^BlockMap, visited: ^Worklist) -> bool {
	log(fn, "-- Begin Global Schedule [early] --")
	defer log(fn, "-- End Global Schedule [early] --")

	stack: [dynamic]^Node
	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]
		assert(n != nil)

		worklist_push(visited, n)

		unhandled_input := false
		for input in n.inputs {
			// input[0] is null for floating nodes since they aren't pinned to control blocks yet obviously
			if input != nil && !worklist_contains(visited, input) {
				append(&stack, input)
				unhandled_input = true
				break
			}
		}

		if unhandled_input do continue

		// This ones ready to schedule (all inputs pinned already)
		if n.kind != .Start && !is_node_pinned(n) {
			deepest_input_bb: ^BasicBlock
			for input in n.inputs {
				if input == nil do continue // control (input[0]) is null sicne this is a floating node
				input_bb := block_map_get_node_block(bm, input)
				assert(input_bb != nil)
				if deepest_input_bb == nil || input_bb.dom_depth > deepest_input_bb.dom_depth {
					deepest_input_bb = input_bb
				}
			}

			log(fn, "moving node v{} to block {}", n.gvn, deepest_input_bb.name)

			block_map_set_node_block(bm, n, deepest_input_bb)
		}

		pop(&stack)
	}

	return true
}

// Picks the final location for the nodes (as late as possible while also pulling code out of loops as much as it can)
final_global_schedule :: proc(fn: ^Function, bm: ^BlockMap, visited: ^Worklist) -> bool {
	log(fn, "-- Begin Global Schedule [final] --")
	defer log(fn, "-- End Global Schedule [final] --")

	stack: [dynamic]^Node
	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]
		assert(n != nil)

		worklist_push(visited, n)

		unhandled_input := false
		for input in n.inputs {
			if input == nil do continue
			if !worklist_contains(visited, input) {
				// start nodes don't have inputs but we still want to add them ig. not super important
				append(&stack, input)
				unhandled_input = true
				break
			}
		}

		if unhandled_input do continue

		if n.kind != .Start && n.inputs[0] == nil { // These can be moved since they aren't required to stay here like calls, volatile stores, jmps, etc you get it
			// place the node before the first use and hoist out of loops where needed
			pin_bb := block_map_get_node_block(bm, n)
			highest_use: ^BasicBlock
			for u in n.users {
				u_bb := block_map_get_node_block(bm, u.n)
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

			block_map_set_node_block(bm, n, final_bb)

			log(fn, "moving node v{} from {} to {}", n.gvn, pin_bb.name, final_bb.name)
		}

		pop(&stack)
	}

	return true
}

local_schedule :: proc(fn: ^Function, blocks: []^BasicBlock, bm: ^BlockMap, visited: ^Worklist) -> bool {
	log(fn, "-- Begin Local Schedule --")
	defer log(fn, "-- End Local Schedule --")

	stack: [dynamic]^Node
	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]
		assert(n != nil)

		worklist_push(visited, n)

		unhandled_input := false
		for input in n.inputs {
			if input == nil do continue
			if !worklist_contains(visited, input) {
				append(&stack, input)
				unhandled_input = true
				break
			}
		}

		if unhandled_input do continue

		if !is_bb_start(n) && !is_bb_term(n) && n.kind != .End {
			// place the node before the first use and hoist out of loops where needed
			pin_bb := block_map_get_node_block(bm, n)

			inject_at(&pin_bb.nodes, len(pin_bb.nodes) - 1, n)
		}

		pop(&stack)
	}

	node_args_scratch: strings.Builder
	defer strings.builder_destroy(&node_args_scratch)
	// logging the final block schedule
	for bb in blocks {
		log(fn, "%%{}:", bb.name)
		for n in bb.nodes {
			node_args := print_node_args(&node_args_scratch, n, bm)
			log(fn, "        v{} = {} {}", n.gvn, n.kind, node_args)
			strings.builder_reset(&node_args_scratch)
		}
	}

	print_node_args :: proc(sb: ^strings.Builder, n: ^Node, bm: ^BlockMap) -> string {
		kind := n.kind
		if kind == .Proj {
			fmt.sbprintf(sb, "v{}", n.inputs[0].gvn )
		} else if kind == .Goto {
			bb := block_map_get_node_block(bm, n.inputs[1])
			fmt.sbprintf(sb, "%%{}", bb.name)
		} else if kind == .Branch {
			bb_t := block_map_get_node_block(bm, n.inputs[2])
			bb_f := block_map_get_node_block(bm, n.inputs[3])
			fmt.sbprintf(sb, "v{} %%{} %%{}", n.inputs[1].gvn, bb_t.name, bb_f.name)
		} else {
			for input, i in n.inputs {
				if kind != .Region && i == 0 do continue
				if input.kind == .IntConst {
					fmt.sbprintf(sb, "${} ", input.extra.derived.(^IntConst).val)
				} else if input.kind == .F32Const {
					fmt.sbprintf(sb, "${} ", input.extra.derived.(^FloatConst).val.(f32))
				} else if input.kind == .F64Const {
					fmt.sbprintf(sb, "${} ", input.extra.derived.(^FloatConst).val.(f32))
				} else if input.kind == .Local {
					fmt.sbprintf(sb, "l.{}.{} ", input.extra.tag, input.gvn)
				} else {
					fmt.sbprintf(sb, "v{} ", input.gvn)
				}
			}
		}

		return strings.to_string(sb^)
	}

	return true
}


// There's probably a goofy ass paper out there that has this same solution idk i just wrote the sombitch from first principles
build_dominator_tree :: proc(fn: ^Function, start: ^BasicBlock, bm: ^BlockMap) -> bool {
	assert(fn != nil)
	assert(start != nil)
	assert(bm != nil)

	log(fn, "-- Begin Dominator Tree Build --")
	defer log(fn, "-- End Dominator Tree Build --")

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
			// FIXME: didn't this change when we added the region memory phis... somehow everything seems to work? lol
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

			log(fn, "{} is dominated by {}", bb.name, highest_bb.name)

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

get_reg :: proc(fn: ^Function, n: ^Node) -> int {
	regalloc := &fn.output.reg_alloc
	lrg_id := find_live_range(regalloc, n)
	lrg := regalloc.lrg_store[lrg_id]
	return lrg.reg
}

register_allocate :: proc(fn: ^Function, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	click_briggs_chaitin(fn, blocks, block_map) or_return
	return true
}

emit :: proc(fn: ^Function, blocks: []^BasicBlock) -> bool {
	log(fn, "-- Begin Instruction Encode --")
	defer log(fn, "-- End Instruction Encode --")
	impl := arch_impl(.Amd64)
	// TODO: we should do some basic bb reordering for fallthroughs to reduce the number of branches we emit but we can do that shit later :P

	// we don't need to actually care about the non-jumps and shit, but having it be like this makes for easy indexing.
	// TODO: see if we can be a little kinder about memory usage here
	starts := make([]int, fn.node_count)
	defer delete(starts)
	sizes  := make([]int, fn.node_count)
	defer delete(sizes)

	// Writing the function body:
	// 1. Write out the rough encoding (assuming short RIP/PC-relative jumps where necessary)
	encode_count := 0
	for block in blocks {
		for n in block.nodes {
			if n.uop != 0 {
				starts[n.gvn] = len(fn.output.data)
				impl.encode(fn, n)
				sizes[n.gvn] = len(fn.output.data) - starts[n.gvn] // the initial encoding size, since we're about to resize some of them where we need to
				encode_count += 1
			}
		}
	}

	// 2. Making allocated RIP/PC-relative displacements bigger where needed

	old_starts := make([]int, fn.node_count)
	defer delete(old_starts)
	copy(old_starts, starts)
	old_sizes := make([]int, fn.node_count)
	defer delete(old_sizes)
	copy(old_sizes, sizes)

	// calculating new starts and sizes
	total_add := 0
	added_this_pass := -1
	for added_this_pass != 0 { // We have to run this a few times to make sure that we get it totally right since there can be knock-on from changing one relo
		added_this_pass = 0
		defer total_add += added_this_pass
		for relo, curr_idx in fn.output.relos {
			if !relo.is_local do continue
			old_size := sizes[relo.n.gvn]
			start := starts[relo.n.gvn]
			target_start := starts[relo.target.gvn]
			to_target_delta_by_start := target_start - start
			encoding_size := impl.encoding_size(relo.n, to_target_delta_by_start)
			if old_size < encoding_size {
				add := encoding_size - old_size
				added_this_pass += add
				sizes[relo.n.gvn] = encoding_size
				for other, other_idx in fn.output.relos {
					if !other.is_local do continue
					if starts[other.target.gvn] > start {
						starts[other.target.gvn] += add
					}
					if other_idx != curr_idx && starts[other.n.gvn] > start {
						starts[other.n.gvn] += add
					}
				}
			}
		}
	}

	// copying all that into the new buffer
	new_data := make([dynamic]u8, len(fn.output.data) + total_add)
	old_end := len(fn.output.data)
	#reverse for relo in fn.output.relos {
		if !relo.is_local do continue
		old_start := old_starts[relo.n.gvn]
		new_start := starts[relo.n.gvn]
		size_delta := sizes[relo.n.gvn] - old_sizes[relo.n.gvn]
		// we'll get a weird offset if the size did change, but we patch it anyways so who cares
		copy(new_data[new_start+size_delta:], fn.output.data[old_start:old_end])
		old_end = old_start
	}

	delete(fn.output.data)
	fn.output.data = new_data

	// 3. Patch the local displacements with the relative locations where possible (function calls/symbols get ignored and will have to be handled by a final link)
	local_relo_count := 0
	non_local_relo_count := 0

	for relo in fn.output.relos {
		if !relo.is_local { // We need a final link order before we can patch function calls and shit
			non_local_relo_count += 1
			continue
		}
		local_relo_count += 1
		start := starts[relo.n.gvn]
		delta_from_starts := starts[relo.target.gvn] - start
		impl.patch_local_relo(fn, relo.n, start, delta_from_starts)
	}

	log(fn, "Successfully encoded {} instructions (patched {} local relocations, {} non-local unpatched relocations)", encode_count, local_relo_count, non_local_relo_count)

	return true
}

add_local_relo :: proc(fn: ^Function, n: ^Node, target: ^Node) {
	relo := LinkRelo {
		is_local = true,
		n = n,
		target = target
	}
	append(&fn.output.relos, relo)
}

add_global_relo :: proc(fn: ^Function, n: ^Node, target: ^Node) {
	relo := LinkRelo {
		is_local = false,
		n = n,
		target = target
	}
	append(&fn.output.relos, relo)
}

