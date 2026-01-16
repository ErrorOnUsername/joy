package opto

import "core:container/bit_array"

// Check out Chapter 20 of Simple (thank you, Cliff): https://github.com/SeaOfNodes/Simple/blob/main/chapter20/README.md

INVALID_LRG :: LiveRangeID(-1)
LiveRangeID :: distinct int
LiveRange :: struct {
	id: LiveRangeID,
	leader: LiveRangeID, // rep of the subset for the union-find of disjointed set
	reg: int,
	available_mask: RegisterMask,
	self_conflicts: [dynamic]^Node,
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

	ctx: RegAllocContext
	ctx.fn = fn
	ctx.lrg_map = make(map[^Node]LiveRangeID)
	defer delete(ctx.lrg_map)

	MAX_REGALLOC_ATTEMPTS :: 7

	attempt := 1
	for !color_graph(&ctx, attempt, blocks, block_map) {
		split_conflicting_live_ranges(&ctx)
		attempt += 1
		assert(attempt <= MAX_REGALLOC_ATTEMPTS)
		log(fn, "Starting Allocation Attempt {}...", attempt)
	}

	log(fn, "Successfully Allocated Registers After {} Round(s) of Graph Coloring", attempt)

	return true
}

color_graph :: proc (ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	ctx.live_range_count = 0
	for i in 0..<ctx.live_range_count {
		bit_array.destroy(ctx.ifg[i])
	}
	delete(ctx.ifg)
	for &lrg in ctx.lrg_store {
		delete(lrg.self_conflicts)
	}
	delete(ctx.lrg_store)
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

	for lrg in ctx.failures {
		live_range := &ctx.lrg_store[lrg]
		assert(live_range.leader == INVALID_LRG)

		if len(live_range.self_conflicts) > 0 {
			split_self_conflicts(ctx, lrg)
		} else if live_range.available_mask == 0 {
			split_empty_regmask(ctx, lrg)
		} else {
			split_loop(ctx, lrg)
		}
	}
}

split_self_conflicts :: proc(ctx: ^RegAllocContext, lrg: LiveRangeID) {
}

split_empty_regmask :: proc(ctx: ^RegAllocContext, lrg: LiveRangeID) {
}

split_loop :: proc(ctx: ^RegAllocContext, lrg: LiveRangeID) {
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
			} else if n.uop != 0 {
				arch := arch_impl(ctx.arch)
				dst_regmask := arch.get_dst_regmask(ctx, n)
				lrg := make_live_range(ctx, n)
				assert(lrg != INVALID_LRG)
				ctx.lrg_store[lrg].available_mask = dst_regmask
				// looking up to inputs to check for self-conflicts
				input_slice_start := 2 if ty_is_mem(n.type) || n.kind == .Load else 3 if n.kind == .Call else 1 // fugly as all getout but leave me alone im annoyed rn
				for input, idx in n.inputs[input_slice_start:] {
					assert(input != nil)
					src_regmask := arch.get_src_regmask(ctx, n, idx + input_slice_start) // the for loop uses a different index for the slice interator since its a whole new slice, not just a sub-iter
					in_lrg := find_live_range(ctx, input)
					if in_lrg == INVALID_LRG do continue
					in_avail := ctx.lrg_store[in_lrg].available_mask
					if in_avail & src_regmask == 0 {
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
		if n.uop != 0 {
			ifg_build_node(ctx, bb, n)
		}
	}

	for i in 1..<len(bb_start.inputs) {
		ifg_merge_live_out(ctx, bb, i, block_map)
	}
}

is_lrg_single_reg :: proc(ctx: ^RegAllocContext, lrg: LiveRangeID) -> bool {
	live_range := &ctx.lrg_store[lrg]
	return live_range.available_mask & -live_range.available_mask == live_range.available_mask
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
		if n.uop != 0 {
			ifg_prop_arch_killmap(ctx, n)
		}

		lrg_is_single_reg := is_lrg_single_reg(ctx, lrg)
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

		if n.uop != 0 {
			arch := arch_impl(ctx.arch)
			n_input_mask := arch.get_src_regmask(ctx, n, i)
			single_reg := n_input_mask & -n_input_mask == n_input_mask
			if single_reg {
				for other_lrg, live in ctx.block_live {
					other_live_range := &ctx.lrg_store[other_lrg]
					assert(other_live_range.leader == INVALID_LRG)
					live_out_mask := arch.get_dst_regmask(ctx, live)
					ranges_overlap := n_input_mask & live_out_mask != 0
					if live != def && live.uop != 0 && ranges_overlap {
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
	assert(n.uop != 0)
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
	return true
}

