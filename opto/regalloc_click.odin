package opto

// Check out Chapter 20 of Simple (thank you, Cliff): https://github.com/SeaOfNodes/Simple/blob/main/chapter20/README.md

LiveRangeID :: distinct int
LiveRange :: struct {
	id: LiveRangeID,
	reg: int,
	available_mask: RegisterMask,
}

RegAllocContext :: struct {
	live_range_count: int,
}

click_briggs_chaitin :: proc(fn: ^Function, blocks: []^BasicBlock) -> bool {
	log(fn, "-- Click/Briggs/Chaitin RegAlloc Begin --")
	defer log(fn, "-- Click/Briggs/Chaitin RegAlloc End --")

	return true
}

