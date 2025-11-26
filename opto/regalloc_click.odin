package opto

// Check out Chapter 20 of Simple (thank you, Cliff): https://github.com/SeaOfNodes/Simple/blob/main/chapter20/README.md

LiveRangeID :: distinct int
LiveRange :: struct {
	id: LiveRangeID,
	leader: ^LiveRange, // rep of the subset for the union-find of disjointed set
	reg: int,
	available_mask: RegisterMask,
}

RegAllocContext :: struct {
	fn: ^Function,
	arch: Arch,
	failures: [dynamic]^LiveRange,
	live_range_count: int,
	lrgs: map[^Node]LiveRange,
}

click_briggs_chaitin :: proc(fn: ^Function, blocks: []^BasicBlock) -> bool {
	log(fn, "-- Click/Briggs/Chaitin RegAlloc Begin --")
	defer log(fn, "-- Click/Briggs/Chaitin RegAlloc End --")

	ctx: RegAllocContext
	ctx.fn = fn
	ctx.lrgs = make(map[^Node]LiveRange) // I don't like this
	defer delete(ctx.lrgs)

	MAX_REGALLOC_ATTEMPTS :: 7

	attempt := 1
	for !color_graph(&ctx, attempt, blocks) {
		assert(attempt <= MAX_REGALLOC_ATTEMPTS)

		split_conflicting_live_ranges(&ctx)

		attempt += 1
		log(fn, "Starting Allocation Attempt {}...", attempt)
	}

	log(fn, "Successfully Allocated Registers After {} Round(s) of Graph Coloring", attempt)

	return true
}

color_graph :: proc (ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock) -> bool {
	allocation_success := build_live_ranges(ctx, attempt_no, blocks) &&
		build_interference_graph(ctx, attempt_no, blocks) &&
		color_interference_graph(ctx, attempt_no, blocks)
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
					log(fn, "Exhausted available registers on {}{}", n.kind, n.gvn)
					record_regalloc_failure(ctx, lrg)
				}
			} else if n.uop != 0 {
				arch := arch_impl(ctx.arch)
				dst_regmask := arch.get_dst_regmask(n)
				lrg := make_live_range(ctx, n)
				assert(lrg != nil)
				lrg.available_mask &= dst_regmask
				src_regmask := arch.get_src_regmask(n)
				// looking up to inputs to check for self-conflicts
				for input in n.inputs[1:] {
					assert(input != nil)
					in_lrg := find_live_range(ctx, input)
					if in_lrg == nil do continue
					if in_lrg.available_mask & src_regmask == 0 {
						log(fn, "Found incompatible register mask from def {}{} to use {}{}", n.kind, n.gvn, input.kind, input.gvn)
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
build_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock) -> bool {
	return true
}

// returns true if coloring succeeded
color_interference_graph :: proc(ctx: ^RegAllocContext, attempt_no: int, blocks: []^BasicBlock) -> bool {
	return true
}

