package opto

import "core:container/bit_array"
import "core:math/bits"
import "core:slice"

// Check out Chapter 20 of Simple (thank you, Cliff): https://github.com/SeaOfNodes/Simple/blob/main/chapter20/README.md

INVALID_LRG :: LiveRangeID(-1)
LiveRangeID :: distinct int
LiveRange :: struct {
	id: LiveRangeID,
	leader: LiveRangeID, // rep of the subset for the union-find of disjointed set
	reg: int,
	available_mask: RegisterMask,
	def: ^Node,
	use: ^Node,
	use_idx: int,
	split_def: ^Node,
	split_use: ^Node,
	single_reg_def_count: int,
	single_reg_use_count: int,
	self_conflicts: [dynamic]^Node,
	adj: [dynamic]^LiveRange,
}

LiveRangeMap :: map[LiveRangeID]^Node

RegAllocContext :: struct {
	fn: ^Function,
	arch: Arch,
	failures: [dynamic]LiveRangeID,
	live_range_count: int,
	lrg_store: [dynamic]LiveRange,
	lrg_map: map[^Node]LiveRangeID,
	ifg: []^bit_array.Bit_Array,

	lrg_build_done: bool,
	work: Worklist,
	bb_out: map[^BasicBlock]LiveRangeMap,
	block_live: LiveRangeMap,
}

click_briggs_chaitin :: proc(fn: ^Function, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	log(fn, "-- Click/Briggs/Chaitin RegAlloc Begin --")
	defer log(fn, "-- Click/Briggs/Chaitin RegAlloc End --")

	ctx := &fn.output.reg_alloc

	ctx.fn = fn
	ctx.lrg_map = make(map[^Node]LiveRangeID)
	ctx.arch = .Amd64

	MAX_REGALLOC_ATTEMPTS :: 7

	insert_callee_saved_values(ctx)

	attempt := 1
	for !color_graph(ctx, attempt, blocks, block_map) {
		split_conflicting_live_ranges(ctx)
		attempt += 1
		assert(attempt <= MAX_REGALLOC_ATTEMPTS)
		log(fn, "Starting Allocation Attempt {}...", attempt)
	}

	log(fn, "Successfully Allocated Registers After {} Round(s) of Graph Coloring", attempt)

	return true
}

insert_callee_saved_values :: proc(ctx: ^RegAllocContext) {
	ret := ctx.fn.end.inputs[0]
	assert(ret != nil)
	assert(ret.kind == .Return) // this must be true or the function is malformed

	arch := arch_impl(ctx.arch)
	callee_save_mask := arch.get_callee_save_regmask(ctx)
	for mask := callee_save_mask; mask != 0; mask &= ~(1 << u64(bits.count_trailing_zeros(mask))) {
		reg := mask & (1 << u64(bits.count_trailing_zeros(mask)))
		assert(reg != 0)
		save := new_node(ctx.fn, .CalleeSave, TY_VOID, 0)
		FIXME_add_input(ctx, ret, save)
	}
}

color_graph :: proc (ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	ctx.live_range_count = 0
	for i in 0..<ctx.live_range_count {
		bit_array.destroy(ctx.ifg[i])
	}
	delete(ctx.ifg)
	ctx.ifg = {}
	for &lrg in ctx.lrg_store {
		delete(lrg.self_conflicts)
	}
	delete(ctx.lrg_store)
	ctx.lrg_store = {}
	clear(&ctx.lrg_map)
	clear(&ctx.failures)
	ctx.lrg_build_done = false
	allocation_success := build_live_ranges(ctx, attempt_no, blocks) &&
		build_interference_graph(ctx, attempt_no, blocks, block_map) &&
		color_interference_graph(ctx, attempt_no, blocks, block_map)
	return allocation_success
}

split_conflicting_live_ranges :: proc(ctx: ^RegAllocContext) {
	log(ctx.fn, "Splitting Conflicting Live Ranges...")

	unimplemented()
}

split_self_conflicts :: proc(ctx: ^RegAllocContext, lrg: ^LiveRange) {
	arch := arch_impl(ctx.arch)
	sc_sort :: proc(a, b: ^Node) -> bool {
		return a.gvn < b.gvn
	}
	conflicts := lrg.self_conflicts[:]
	slice.sort_by(conflicts, sc_sort)

	for def in conflicts {
		assert(find_live_range(ctx, def) == lrg.id)

		if def.kind == .Phi {
			insert_split_before(ctx, def, 1, lrg)
		}

		if arch_is_valid_op(def.uop) && arch.is_two_address_op(ctx, def) {
			insert_split_before(ctx, def, arch.get_two_address_index(ctx, def), lrg)
		}

		for use in def.users {
			use_node := use.n
			is_not_loop_bound_phi := use_node.kind == .Phi // FIXME: theres a check if we're in a loop that stops this
			is_two_address_split_point := arch_is_valid_op(use_node.uop) && arch.is_two_address_op(ctx, use_node) && use_node.inputs[arch.get_two_address_index(ctx, use_node)] == def
			if is_not_loop_bound_phi || is_two_address_split_point {
				idx, found := slice.linear_search(use_node.inputs, def)
				assert(found)
				insert_split_before(ctx, use_node, idx, lrg)
			}
		}
	}
}

split_empty_regmask_simple :: proc(ctx: ^RegAllocContext, lrg: ^LiveRange) {
	if lrg.single_reg_def_count > 0 {
		insert_split_after(ctx, lrg.def, lrg)
	}
	if lrg.single_reg_use_count > 0 {
		insert_split_before(ctx, lrg.use, lrg.use_idx, lrg)
	}
}

split_loop :: proc(ctx: ^RegAllocContext, lrg: ^LiveRange) {
	unimplemented()
}

insert_split_after :: proc(ctx: ^RegAllocContext, def: ^Node, lrg: ^LiveRange) {
	unimplemented()
}

insert_split_before :: proc(ctx: ^RegAllocContext, def: ^Node, in_idx: int, lrg: ^LiveRange) {
	unimplemented()
}

// returns true if no hard register conflicts
build_live_ranges :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock) -> bool {
	fn := ctx.fn
	for bb in blocks {
		for n in bb.nodes {
			// We don't care about the mem phis on regions since that's just for SON book-keeping
			if n.kind == .Phi && !ty_is_mem(n.type) {
				lrg := find_live_range(ctx, n)
				if lrg == INVALID_LRG {
					for merge in n.inputs {
						merge_lrg := find_live_range(ctx, merge)
						if merge_lrg != INVALID_LRG {
							lrg = merge_lrg
							break
						}
					}
				}
				if lrg == INVALID_LRG {
					lrg = make_live_range(ctx, n)
				}
				// all the inputs of a phi use the same reg
				lrg = merge_live_range(ctx, lrg, n)
				for input in n.inputs[1:] {
					lrg = merge_live_range(ctx, lrg, input)
				}
				if ctx.lrg_store[lrg].available_mask == 0 {
					log(fn, "Exhausted available registers on merge at {}{}", n.kind, n.gvn)
					record_regalloc_failure(ctx, lrg)
				}
			} else if arch_is_valid_op(n.uop) && n.kind != .Start {
				def_live_range(ctx, n)

				// looking up to inputs to check for self-conflicts
				arch := arch_impl(ctx.arch)
				input_slice_start := 2 if ty_is_mem(n.type) || n.kind == .Load else 3 if n.kind == .Call else 1 // fugly as all getout but leave me alone im annoyed rn
				for input, idx in n.inputs[input_slice_start:] {
					assert(input != nil)
					src_regmask := arch.get_src_regmask(ctx, n, idx + input_slice_start) // the for loop uses a different index for the slice interator since its a whole new slice, not just a sub-iter
					in_lrg := find_live_range(ctx, input)
					if in_lrg == INVALID_LRG do continue
					in_lrg_ptr := &ctx.lrg_store[in_lrg]
					in_avail := in_lrg_ptr.available_mask
					in_lrg_ptr.available_mask &= src_regmask
					if in_lrg_ptr.available_mask == 0 {
						src_mask_str := arch_get_register_mask_str(ctx.arch, src_regmask)
						defer delete(src_mask_str)
						in_mask_str := arch_get_register_mask_str(ctx.arch, in_avail)
						defer delete(in_mask_str)
						log(fn, "Found incompatible register mask from def {}{} (available: {}) to use {}{} (requires: {})", input.kind, input.gvn, in_mask_str, n.kind, n.gvn, src_mask_str)
						record_regalloc_failure(ctx, in_lrg)
					}
				}
			}
		}
	}

	ctx.lrg_build_done = true

	return len(ctx.failures) == 0
}

record_regalloc_failure :: proc(ctx: ^RegAllocContext, range: LiveRangeID) {
	assert(range != INVALID_LRG)
	live_range := &ctx.lrg_store[range]
	assert(live_range.leader == INVALID_LRG) // must be the leader since it would've created its own live range on a conflict
	append(&ctx.failures, range)
}

def_live_range :: proc(ctx: ^RegAllocContext, n: ^Node) {
	arch := arch_impl(ctx.arch)
	assert(arch_is_valid_op(n.uop))
	dst_regmask := arch.get_dst_regmask(ctx, n)
	if dst_regmask == 0 do return // stores and shit shouldn't produce a live range
	lrg := make_live_range(ctx, n)
	assert(lrg != INVALID_LRG)
	live_range := &ctx.lrg_store[lrg]
	live_range.available_mask = dst_regmask
	if live_range.def == nil || is_live_range_single_reg(live_range) {
		live_range.def = n
	}
}

make_live_range :: proc(ctx: ^RegAllocContext, n: ^Node) -> LiveRangeID {
	assert(!ctx.lrg_build_done)
	lrg := find_live_range(ctx, n)
	if lrg != INVALID_LRG do return lrg
	new_lrg: LiveRange
	id := LiveRangeID(ctx.live_range_count)
	new_lrg.id = id
	new_lrg.leader = INVALID_LRG
	assert(!(n in ctx.lrg_map))
	append(&ctx.lrg_store, new_lrg)
	ctx.live_range_count += 1
	ctx.lrg_map[n] = id
	return id
}

find_live_range :: proc(ctx: ^RegAllocContext, n: ^Node) -> LiveRangeID {
	if !(n in ctx.lrg_map) do return INVALID_LRG
	id := ctx.lrg_map[n]
	found_id := get_or_update_live_range_leader(ctx, id)
	if found_id != id{ // we didn't have the actual leader before
		ctx.lrg_map[n] = found_id // put the new post-rollup leader back in the slot
	}
	return found_id
}

get_or_update_live_range_leader :: proc(ctx: ^RegAllocContext, range: LiveRangeID) -> LiveRangeID {
	// FIXME: this is silly
	assert(range != INVALID_LRG)
	if ctx.lrg_store[range].leader == INVALID_LRG do return range
	if ctx.lrg_store[ctx.lrg_store[range].leader].leader == INVALID_LRG do return ctx.lrg_store[range].leader
	return update_live_range_leader(ctx, range)
}

update_live_range_leader :: proc(ctx: ^RegAllocContext, range: LiveRangeID) -> LiveRangeID {
	leader := ctx.lrg_store[ctx.lrg_store[range].leader].leader
	for ctx.lrg_store[leader].leader != INVALID_LRG {
		leader = ctx.lrg_store[leader].leader
	}

	walk := range
	for walk != leader {
		new_walk := ctx.lrg_store[walk].leader
		ctx.lrg_store[walk].leader = leader
		walk = new_walk
	}

	return leader
}

merge_live_range :: proc(ctx: ^RegAllocContext, id: LiveRangeID, n: ^Node) -> LiveRangeID {
	assert(ctx.lrg_store[id].leader == INVALID_LRG)
	n_range_id := find_live_range(ctx, n)
	if n_range_id == INVALID_LRG || id == n_range_id do return id
	new_leader := id if id < n_range_id else n_range_id
	other := n_range_id if id < n_range_id else id

	new_leader_range := &ctx.lrg_store[new_leader]
	other_range := &ctx.lrg_store[other]

	other_range.leader = new_leader
	new_leader_range.available_mask &= other_range.available_mask

	return new_leader
}

// returns true if there we no confliting live ranges
build_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	worklist_init(&ctx.work, ctx.fn.node_count)
	ctx.ifg = make([]^bit_array.Bit_Array, ctx.live_range_count)
	for i in 0..<ctx.live_range_count {
		ctx.ifg[i] = bit_array.create(ctx.live_range_count)
	}

	for bb in blocks {
		assert(!worklist_contains(&ctx.work, bb.nodes[0]))
		worklist_push(&ctx.work, bb.nodes[0])
	}

	for {
		x := worklist_pop(&ctx.work)
		if x == nil do break

		assert(is_bb_start(x))
		bb := block_map_get_node_block(block_map, x)

		ifg_build_block(ctx, bb, block_map)
	}

	return len(ctx.failures) == 0
}

ifg_build_block :: proc(ctx: ^RegAllocContext, bb: ^BasicBlock, block_map: ^BlockMap) {
	clear(&ctx.block_live)

	bb_start := bb.nodes[0]

	#reverse for n in bb.nodes {
		if arch_is_valid_op(n.uop) {
			ifg_build_node(ctx, bb, n)
		}
	}

	for i in 1..<len(bb_start.inputs) {
		ifg_merge_live_out(ctx, bb, i, block_map)
	}
}

is_lrg_id_single_reg :: proc(ctx: ^RegAllocContext, lrg: LiveRangeID) -> bool {
	live_range := &ctx.lrg_store[lrg]
	return live_range.available_mask & -live_range.available_mask == live_range.available_mask
}

is_live_range_single_reg :: proc(lrg: ^LiveRange) -> bool {
	return lrg.available_mask & -lrg.available_mask == lrg.available_mask
}

ifg_build_node :: proc(ctx: ^RegAllocContext, bb: ^BasicBlock, n: ^Node) {
	lrg := find_live_range(ctx, n)
	if lrg != INVALID_LRG {
		check_for_self_conflict(ctx, n, lrg)
		delete_key(&ctx.block_live, lrg)
	}

	if n.kind == .Phi {
		return // ignore these for now
	}

	if lrg != INVALID_LRG {
		if arch_is_valid_op(n.uop) {
			ifg_prop_arch_killmap(ctx, n)
		}

		lrg_is_single_reg := is_lrg_id_single_reg(ctx, lrg)
		live_range := &ctx.lrg_store[lrg]
		for other_lrg, live in ctx.block_live {
			other_live_range := &ctx.lrg_store[other_lrg]
			assert(other_live_range.leader == INVALID_LRG)
			if other_lrg != lrg && other_live_range.available_mask & live_range.available_mask != 0 {
				if lrg_is_single_reg {
					n_reg := arch_get_register_mask_str(ctx.arch, live_range.available_mask)
					defer delete(n_reg)
					live_regs := arch_get_register_mask_str(ctx.arch, other_live_range.available_mask)
					defer delete(live_regs)
					log(ctx.fn, "value {}{} requires single register '{}', but that interferes with live value {}{}({})", n.kind, n.gvn, n_reg, live.kind, live.gvn, live_regs)
					record_regalloc_failure(ctx, other_lrg)
				} else {
					ifg_add(ctx, lrg, other_lrg)
				}
			}
		}
	}

	for i in 1..<len(n.inputs) {
		def := n.inputs[i]
		if def == nil do continue
		def_lrg := find_live_range(ctx, def)
		if def_lrg == INVALID_LRG do continue

		// we need to make sure the value uses don't conflict as well
		check_for_self_conflict(ctx, def, def_lrg)

		if arch_is_valid_op(n.uop) {
			arch := arch_impl(ctx.arch)
			n_input_mask := arch.get_src_regmask(ctx, n, i)
			single_reg := n_input_mask & -n_input_mask == n_input_mask
			if single_reg {
				for other_lrg, live in ctx.block_live {
					other_live_range := &ctx.lrg_store[other_lrg]
					assert(other_live_range.leader == INVALID_LRG)
					live_out_mask := arch.get_dst_regmask(ctx, live)
					ranges_overlap := n_input_mask & live_out_mask != 0
					if live != def && arch_is_valid_op(live.uop) && ranges_overlap {
						other_live_range.available_mask &= ~n_input_mask
						if other_live_range.available_mask == 0 {
							n_regs := arch_get_register_mask_str(ctx.arch, n_input_mask)
							defer delete(n_regs)
							live_regs := arch_get_register_mask_str(ctx.arch, other_live_range.available_mask)
							defer delete(live_regs)
							log(ctx.fn, "ifg-build: single-register input of {}{}({}) doesn't conform to output of value {}{}({})", n.kind, n.gvn, n_regs, live.kind, live.gvn, live_regs)
							record_regalloc_failure(ctx, other_lrg)
						}
					}
				}
			}
		}

		// da inputs are now live >:D
		ctx.block_live[def_lrg] = def
	}
}

ifg_add :: proc(ctx: ^RegAllocContext, a: LiveRangeID, b: LiveRangeID) {
	// the lower of the two live ranges always wins
	if a < b {
		lrg_conflicts := ctx.ifg[a]
		ensure(bit_array.set(lrg_conflicts, b))
	} else {
		lrg_conflicts := ctx.ifg[b]
		ensure(bit_array.set(lrg_conflicts, a))
	}
}

ifg_prop_arch_killmap :: proc(ctx: ^RegAllocContext, n: ^Node) {
	assert(arch_is_valid_op(n.uop))
	lrg := find_live_range(ctx, n)
	arch := arch_impl(ctx.arch)
	kill_mask := arch.get_kill_regmask(ctx, n)
	if kill_mask == 0 do return

	for other_lrg, live in ctx.block_live {
		other_live_range := &ctx.lrg_store[other_lrg]
		mask_overlaps := other_live_range.available_mask & kill_mask != 0
		if mask_overlaps {
			other_live_range.available_mask &= ~kill_mask
			if other_live_range.available_mask == 0 {
				log(ctx.fn, "ifg-build: {}{} killed all the registers of {}{}. need to split...", n.kind, n.gvn, live.kind, live.gvn)
				record_regalloc_failure(ctx, other_lrg)
			}
		}
	}
}

ifg_merge_live_out :: proc(ctx: ^RegAllocContext, bb: ^BasicBlock, pred_idx: int, block_map: ^BlockMap) {
	bb_start := bb.nodes[0]
	assert(bb_start != nil)
	assert(is_bb_start(bb_start))
	pred_link := bb_start.inputs[pred_idx]
	assert(pred_link != nil)
	pred_bb := block_map_get_node_block(block_map, pred_link)
	assert(pred_bb != nil)
	pred_start := pred_bb.nodes[0]

	if !(pred_bb in ctx.bb_out) {
		ctx.bb_out[pred_bb] = {}
	}

	out_map := &ctx.bb_out[pred_bb]

	for lrg, live in ctx.block_live {
		if lrg in out_map {
			check_is_conflicting(ctx, live, lrg, out_map[lrg])
		} else {
			out_map[lrg] = live
			if !worklist_contains(&ctx.work, pred_start) {
				worklist_push(&ctx.work, pred_start)
			}
		}
	}
}

check_for_self_conflict :: proc(ctx: ^RegAllocContext, n: ^Node, lrg: LiveRangeID) {
	other_active := ctx.block_live[lrg]
	if other_active != nil && n != other_active {
		live_range := &ctx.lrg_store[lrg]
		log(ctx.fn, "ifg-build: {}{} using same live range as {}{}", n.kind, n.gvn, other_active.kind, other_active.gvn)
		append(&live_range.self_conflicts, other_active)
		append(&live_range.self_conflicts, n)
		record_regalloc_failure(ctx, lrg)
	}
}

check_is_conflicting :: proc(ctx: ^RegAllocContext, n: ^Node, lrg: LiveRangeID, maybe_prior: ^Node) {
	if maybe_prior != nil && n != maybe_prior {
		live_range := &ctx.lrg_store[lrg]
		log(ctx.fn, "ifg-build: {}{} using same live range as {}{}", n.kind, n.gvn, maybe_prior.kind, maybe_prior.gvn)
		append(&live_range.self_conflicts, maybe_prior)
		append(&live_range.self_conflicts, n)
		record_regalloc_failure(ctx, lrg)
	}
}

// returns true if coloring succeeded
color_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	for i in 0..<len(ctx.lrg_store) {
		lrg := &ctx.lrg_store[i]
		assert(lrg.id != INVALID_LRG)
		intrf_set := ctx.ifg[lrg.id]
		iter := bit_array.make_iterator(intrf_set)
		id, it_ok := bit_array.iterate_by_set(&iter)
		for it_ok {
			defer id, it_ok = bit_array.iterate_by_set(&iter)
			other_lrg := &ctx.lrg_store[id]
			append(&lrg.adj, other_lrg)
			append(&other_lrg.adj, lrg)
		}
	}

	work := 0
	stack_len := 0
	color_stack := make([]^LiveRange, len(ctx.lrg_store))
	defer delete(color_stack)
	for i in 0..<len(ctx.lrg_store) {
		lrg := &ctx.lrg_store[i]
		assert(lrg.id != INVALID_LRG)
		color_stack[stack_len] = lrg
		if len(lrg.adj) < bits.count_ones(lrg.available_mask) {
			color_stack_swap(color_stack, work, stack_len)
			work += 1
		}
		stack_len += 1
	}

	ptr := 0
	for ptr < len(color_stack) {
		shuffle_next_best_to_front(color_stack, ptr, work)

		lrg := color_stack[ptr]
		ptr += 1

		if ptr > work {
			work = ptr
		}

		for adj in lrg.adj {
			if remove_check_made_low_risk(adj, lrg) {
				adj_stack_idx := work
				for color_stack[adj_stack_idx] != adj {
					adj_stack_idx += 1
				}
				color_stack_swap(color_stack, work, adj_stack_idx)
				work += 1
			}
		}
	}

	for ptr > 0 {
		ptr -= 1
		lrg := color_stack[ptr]
		for adj in lrg.adj {
			append(&adj.adj, lrg)
			adj_reg := adj.reg
			if adj_reg != -1 {
				lrg.available_mask &= ~RegisterMask(1 << uint(adj_reg))
			}
		}

		if lrg.available_mask == 0 {
			log(ctx.fn, "failed to assign a register to lrg {} ({}{})", lrg.id, lrg.def.kind, lrg.def.gvn)
			lrg.reg = -1
			record_regalloc_failure(ctx, lrg.id)
		} else {
			reg := bits.count_trailing_zeros(lrg.available_mask)
			if bits.count_ones(lrg.available_mask) > 1 {
				reg = bias_color(ctx, lrg, reg, lrg.available_mask)
			}
			lrg.reg = reg
		}
	}

	return len(ctx.failures) == 0
}

remove_check_made_low_risk :: proc(a: ^LiveRange, b: ^LiveRange) -> bool {
	idx := -1
	for adj, i in a.adj {
		if adj == b {
			idx = i
		}
	}
	assert(idx != -1)
	about_to_go_trivial := len(a.adj) == bits.count_ones(a.available_mask)
	unordered_remove(&a.adj, idx)
	return about_to_go_trivial
}

color_stack_swap :: proc(color_stack: []^LiveRange, a: int, b: int) {
	tmp := color_stack[a]
	color_stack[a] = color_stack[b]
	color_stack[b] = tmp
}

shuffle_next_best_to_front :: proc(color_stack: []^LiveRange, ptr: int, work: int) {
	if ptr == work {
		risky := pick_risky(color_stack, ptr)
		color_stack_swap(color_stack, ptr, risky)
	}

	best_idx := ptr
	best_lrg := color_stack[best_idx]
	for i in ptr + 1..<work {
		test_lrg := color_stack[i]
		if is_better_lrg(best_lrg, test_lrg) {
			best_lrg = test_lrg
			best_idx = i
		}
	}

	color_stack_swap(color_stack, ptr, best_idx)
}

pick_risky :: proc(color_stack: []^LiveRange, ptr: int) -> int {
	best_idx := ptr
	best_score := risk_score(color_stack[ptr])
	for i in ptr + 1..<len(color_stack) {
		if best_score == 9999 do return best_idx
		iter_score := risk_score(color_stack[i])
		if iter_score > best_score {
			best_idx = i
			best_score = iter_score
		}
	}
	return best_idx
}

risk_score :: proc(lrg: ^LiveRange) -> int {
	if lrg.def.kind == .CalleeSave {
		return 9998
	}
	if lrg.split_def != nil && lrg.split_def.inputs[1].kind == .CalleeSave && lrg.split_use != nil && lrg.split_use.users[0].n.kind == .Return {
		return 9999
	}
	return 100
}

has_split :: proc(lrg: ^LiveRange) -> bool {
	return lrg.split_use != nil || lrg.split_def != nil
}

is_better_lrg :: proc(curr: ^LiveRange, test: ^LiveRange) -> bool {
	if is_live_range_single_reg(curr) != is_live_range_single_reg(test) {
		return is_live_range_single_reg(curr) // we want to leave single-reg live ranges for last
	}
	if has_split(curr) != has_split(test) {
		return has_split(test) // take the one with the split if we have it
	}
	return bits.count_ones(curr.available_mask) < bits.count_ones(test.available_mask) // take the one with more available registers
}

bias_color :: proc(ctx: ^RegAllocContext, lrg: ^LiveRange, reg: int, mask: RegisterMask) -> int {
	return reg
}
