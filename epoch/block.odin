package epoch


BasicBlock :: struct {
	id:    int,
	nodes: [dynamic]^Node,
	succ:  []^Node,
	dom:   ^Node,
}

BlockMap :: struct {
	blocks: []^BasicBlock, // keyed by node gvn
}

block_map_create :: proc(fn: ^Function) -> BlockMap {
	bm: BlockMap
	bm.blocks = make([]^BasicBlock, fn.node_count)
	return bm
}

block_map_destroy :: proc(bm: ^BlockMap) {
	delete(bm.blocks)
}

block_map_set_node_block :: proc(bm: ^BlockMap, n: ^Node, bb: ^BasicBlock) {
	assert(int(n.gvn) < len(bm.blocks))
	bm.blocks[n.gvn] = bb
}

block_map_get_node_block :: proc(bm: ^BlockMap, n: ^Node) -> ^BasicBlock {
	assert(int(n.gvn) < len(bm.blocks))
	return bm.blocks[n.gvn]
}

