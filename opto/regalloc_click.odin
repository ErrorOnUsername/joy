package opto

// Check out Chapter 20 of Simple (thank you, Cliff): https://github.com/SeaOfNodes/Simple/blob/main/chapter20/README.md

LiveRangeID :: distinct int
LiveRange :: struct {
	id: LiveRangeID,
	leader: ^LiveRange, // rep of the subset for the union-find of disjointed set
	reg: int,
	available_mask: RegisterMask,
	self_conflicts: [dynamic]^Node,
}

LiveRangeMap :: map[^LiveRange]^Node

RegAllocContext :: struct {
	fn: ^Function,
	arch: Arch,
	failures: [dynamic]^LiveRange,
	live_range_count: int,
	lrgs: map[^Node]LiveRange,

	work: Worklist,
	bb_out: map[^BasicBlock]LiveRangeMap,
	block_live: LiveRangeMap,
}

click_briggs_chaitin :: proc(fn: ^Function, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	log(fn, "-- Click/Briggs/Chaitin RegAlloc Begin --")
	defer log(fn, "-- Click/Briggs/Chaitin RegAlloc End --")

	ctx: RegAllocContext
	ctx.fn = fn
	ctx.lrgs = make(map[^Node]LiveRange) // I don't like this
	defer delete(ctx.lrgs)

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
	clear(&ctx.lrgs)
	clear(&ctx.failures)
	allocation_success := build_live_ranges(ctx, attempt_no, blocks) &&
		build_interference_graph(ctx, attempt_no, blocks, block_map) &&
		color_interference_graph(ctx, attempt_no, blocks, block_map)
	return allocation_success
}

split_conflicting_live_ranges :: proc(ctx: ^RegAllocContext) {
	log(ctx.fn, "Splitting Conflicting Live Ranges...")
}

// returns true if no hard register conflicts
build_live_ranges :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock) -> bool {
	fn := ctx.fn
	for bb in blocks {
		for n in bb.nodes {
			// We don't care about the mem phis on regions since that's just for SON book-keeping
			if n.kind == .Phi && !ty_is_mem(n.type) {
				lrg := find_live_range(ctx, n)
				if lrg == nil {
					for merge in n.inputs {
						merge_lrg := find_live_range(ctx, merge)
						if lrg != nil {
							lrg = merge_lrg
							break
						}
					}
				}
				if lrg == nil {
					lrg = make_live_range(ctx, n)
				}
				// all the inputs of a phi use the same reg
				lrg = merge_live_range(ctx, lrg, n)
				for input in n.inputs[1:] {
					lrg = merge_live_range(ctx, lrg, input)
				}
				if lrg.available_mask == 0 {
					log(fn, "Exhausted available registers on merge at {}{}", n.kind, n.gvn)
					record_regalloc_failure(ctx, lrg)
				}
			} else if n.uop != 0 {
				arch := arch_impl(ctx.arch)
				dst_regmask := arch.get_dst_regmask(ctx, n)
				lrg := make_live_range(ctx, n)
				assert(lrg != nil)
				lrg.available_mask = dst_regmask
				// looking up to inputs to check for self-conflicts
				input_slice_start := 2 if ty_is_mem(n.type) || n.kind == .Load else 3 if n.kind == .Call else 1 // fugly as all getout but leave me alone im annoyed rn
				for input, idx in n.inputs[input_slice_start:] {
					assert(input != nil)
					src_regmask := arch.get_src_regmask(ctx, n, idx + input_slice_start) // the for loop uses a different index for the slice interator since its a whole new slice, not just a sub-iter
					in_lrg := find_live_range(ctx, input)
					if in_lrg == nil do continue
					if in_lrg.available_mask & src_regmask == 0 {
						src_mask_str := arch_get_register_mask_str(ctx.arch, src_regmask)
						defer delete(src_mask_str)
						in_mask_str := arch_get_register_mask_str(ctx.arch, in_lrg.available_mask)
						defer delete(in_mask_str)
						log(fn, "Found incompatible register mask from def {}{} (available: {}) to use {}{} (requires: {})", input.kind, input.gvn, in_mask_str, n.kind, n.gvn, src_mask_str)
						record_regalloc_failure(ctx, in_lrg)
					}
				}
			}
		}
	}

	return len(ctx.failures) == 0
}

record_regalloc_failure :: proc(ctx: ^RegAllocContext, range: ^LiveRange) {
	assert(range != nil)
	assert(range.leader == nil) // must be the leader since it would've created its own live range on a conflict
	append(&ctx.failures, range)
}

make_live_range :: proc(ctx: ^RegAllocContext, n: ^Node) -> ^LiveRange {
	lrg := find_live_range(ctx, n)
	if lrg != nil do return lrg
	assert(!(n in ctx.lrgs))
	ctx.lrgs[n] = {}
	lrg = &ctx.lrgs[n]
	ctx.live_range_count += 1
	lrg.id = LiveRangeID(ctx.live_range_count)
	return lrg
}

find_live_range :: proc(ctx: ^RegAllocContext, n: ^Node) -> ^LiveRange {
	if !(n in ctx.lrgs) do return nil
	lrg := &ctx.lrgs[n]
	found_lrg := get_or_update_live_range_leader(ctx, lrg)
	if found_lrg != lrg { // we didn't have the actual leader before
		ctx.lrgs[n] = found_lrg^ // put the new post-rollup leader back in the slot
	}
	return found_lrg
}

get_or_update_live_range_leader :: proc(ctx: ^RegAllocContext, range: ^LiveRange) -> ^LiveRange {
	assert(range != nil)
	if range.leader == nil do return range
	if range.leader.leader == nil do return range.leader
	return update_live_range_leader(ctx, range)
}

update_live_range_leader :: proc(ctx: ^RegAllocContext, range: ^LiveRange) -> ^LiveRange {
	leader := range.leader.leader
	for leader.leader != nil {
		leader = leader.leader
	}

	walk := range
	for walk != leader {
		new_walk := walk.leader
		walk.leader = leader
		walk = new_walk
	}

	return leader
}

merge_live_range :: proc(ctx: ^RegAllocContext, range: ^LiveRange, n: ^Node) -> ^LiveRange {
	assert(range.leader == nil)
	n_range := find_live_range(ctx, n)
	if n_range == nil || range == n_range do return range
	new_leader := range if range.id < n_range.id else n_range
	other := n_range if range.id < n_range.id else range

	other.leader = new_leader
	new_leader.available_mask = new_leader.available_mask & other.available_mask

	return new_leader
}

// returns true if there we no confliting live ranges
build_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	worklist_init(&ctx.work, ctx.fn.node_count)

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

ifg_build_node :: proc(ctx: ^RegAllocContext, bb: ^BasicBlock, n: ^Node) {
	lrg := find_live_range(ctx, n)
	if lrg != nil {
		check_for_self_conflict(ctx, n, lrg)
		delete_key(&ctx.block_live, lrg)
	}

	if n.kind == .Phi {
		return // ignore these for now
	}

	if lrg != nil {
		if n.uop != 0 {
			ifg_prop_arch_killmap(ctx, n)
		}

		for other_lrg, live in ctx.block_live {
			assert(other_lrg.leader == nil)
			if lrg != other_lrg && other_lrg.available_mask & lrg.available_mask != 0 {
				n_regs := arch_get_register_mask_str(ctx.arch, lrg.available_mask)
				defer delete(n_regs)
				live_regs := arch_get_register_mask_str(ctx.arch, other_lrg.available_mask)
				defer delete(live_regs)
				log(ctx.fn, "ifg-build: live value {}{}({}) interferes with other live value {}{}({})", n.kind, n.gvn, n_regs, live.kind, live.gvn, live_regs)
				record_regalloc_failure(ctx, other_lrg)
			}
		}
	}

	for i in 1..<len(n.inputs) {
		def := n.inputs[i]
		if def == nil do continue
		def_lrg := find_live_range(ctx, def)
		if def_lrg == nil do continue

		// we need to make sure the value uses don't conflict as well
		check_for_self_conflict(ctx, def, def_lrg)

		if n.uop != 0 {
			arch := arch_impl(ctx.arch)
			n_input_mask := arch.get_src_regmask(ctx, n, i)
			single_reg := n_input_mask & -n_input_mask == n_input_mask
			if single_reg {
				for other_lrg, live in ctx.block_live {
					assert(other_lrg.leader == nil)
					live_out_mask := arch.get_dst_regmask(ctx, live)
					ranges_overlap := n_input_mask & live_out_mask != 0
					if live != def && live.uop != 0 && ranges_overlap {
						other_lrg.available_mask = other_lrg.available_mask & ~n_input_mask
						if other_lrg.available_mask == 0 {
							n_regs := arch_get_register_mask_str(ctx.arch, n_input_mask)
							defer delete(n_regs)
							live_regs := arch_get_register_mask_str(ctx.arch, other_lrg.available_mask)
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

ifg_prop_arch_killmap :: proc(ctx: ^RegAllocContext, n: ^Node) {
	assert(n.uop != 0)
	lrg := find_live_range(ctx, n)
	arch := arch_impl(ctx.arch)
	kill_mask := arch.get_kill_regmask(ctx, n)
	if kill_mask == 0 do return

	for other_lrg, live in ctx.block_live {
		mask_overlaps := other_lrg.available_mask & kill_mask != 0
		if mask_overlaps {
			other_lrg.available_mask = other_lrg.available_mask & ~kill_mask
			if other_lrg.available_mask == 0 {
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
	pred := bb_start.inputs[pred_idx]
	assert(pred != nil)
	assert(is_bb_start(pred))
	pred_bb := block_map_get_node_block(block_map, pred)
	assert(pred_bb != nil)

	out_map := &ctx.bb_out[pred_bb]

	for lrg, live in ctx.block_live {
		if lrg in out_map {
			check_is_conflicting(ctx, live, lrg, out_map[lrg])
		} else {
			out_map[lrg] = live
			if !worklist_contains(&ctx.work, pred) {
				worklist_push(&ctx.work, pred)
			}
		}
	}
}

check_for_self_conflict :: proc(ctx: ^RegAllocContext, n: ^Node, lrg: ^LiveRange) {
	other_active := ctx.block_live[lrg]
	if other_active != nil && n != other_active {
		log(ctx.fn, "ifg-build: {}{} using same live range as {}{}", n.kind, n.gvn, other_active.kind, other_active.gvn)
		append(&lrg.self_conflicts, other_active)
		append(&lrg.self_conflicts, n)
		record_regalloc_failure(ctx, lrg)
	}
}

check_is_conflicting :: proc(ctx: ^RegAllocContext, n: ^Node, lrg: ^LiveRange, maybe_prior: ^Node) {
	if maybe_prior != nil && n != maybe_prior {
		log(ctx.fn, "ifg-build: {}{} using same live range as {}{}", n.kind, n.gvn, maybe_prior.kind, maybe_prior.gvn)
		append(&lrg.self_conflicts, maybe_prior)
		append(&lrg.self_conflicts, n)
		record_regalloc_failure(ctx, lrg)
	}
}

// returns true if coloring succeeded
color_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock, block_map: ^BlockMap) -> bool {
	return true
}

