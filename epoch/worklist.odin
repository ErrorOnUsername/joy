package epoch

import "core:mem"


Worklist :: struct {
	nodes: [dynamic]^Node,
	visited_bits: []u64, // bitset indexed by gvn (is there a Odin-y way to do this?)
}

worklist_init :: proc(w: ^Worklist, node_count: int, a: mem.Allocator) {
	words_for_node_count := max(node_count / 64, 1)
	w.visited_bits = make([]u64, words_for_node_count, a)
}

worklist_deinit :: proc(w: ^Worklist) {
	delete(w.nodes)
	delete(w.visited_bits)
}

@(private = "file")
get_node_visited_location :: proc(n: ^Node) -> (word_idx: int, mask: u64) {
	word_idx = int(n.gvn / 64)
	mask     = 1 << (n.gvn % 64)
	return
}

worklist_contains :: proc(w: ^Worklist, n: ^Node) -> bool {
	word_i, mask := get_node_visited_location(n)
	return w.visited_bits[word_i] & mask != 0
}

worklist_push :: proc(w: ^Worklist, n: ^Node) {
	append(&w.nodes, n)
	word_i, mask := get_node_visited_location(n)
	w.visited_bits[word_i] |= mask
}

worklist_pop :: proc(w: ^Worklist) -> ^Node {
	if len(w.nodes) == 0 {
		return nil
	}

	n := pop(&w.nodes)
	word_i, mask := get_node_visited_location(n)
	w.visited_bits[word_i] &= ~mask
	return n
}

worklist_peek :: proc(w: ^Worklist) -> ^Node {
	return w.nodes[len(w.nodes) - 1]
}

