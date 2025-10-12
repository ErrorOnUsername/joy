package opto

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

dump_module_gviz :: proc(mod: ^Module, out_path: string) -> bool {
	sb: strings.Builder
	defer strings.builder_destroy(&sb)

	fmt.sbprintfln(&sb, "digraph {} {{", mod.name)

	fmt.sbprintln(&sb, "rankdir=\"BT\";")

	for sym in mod.symbols {
		asm_symbol(sym, &sb) or_return
		fmt.sbprint(&sb, "\n")
	}

	fmt.sbprintln(&sb, "}")

	err := os.write_entire_file_or_err(out_path, sb.buf[:])
	if err != nil {
		fmt.printfln("Failed to dump module '{}'. Reason: {}", mod.name, os.error_string(err))
		return false
	}

	return true
}

asm_symbol :: proc(sym: ^Symbol, sb: ^strings.Builder) -> bool {
	switch s in sym.derived {
		case ^Function:
			fmt.sbprintfln(sb, "subgraph {} {{", s.name)

			print_fn_gv(s, sb) or_return

			fmt.sbprintln(sb, "}")
		case ^Global:
			// fmt.sbprintfln(sb, "{};", s.name)
	}

	return true
}

print_fn_gv :: proc(fn: ^Function, sb: ^strings.Builder) -> bool {
	wl: Worklist
	worklist_init(&wl, fn.node_count)
	defer worklist_deinit(&wl)

	stack: [dynamic]^Node
	defer delete(stack)

	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]

		worklist_push(&wl, n)

		unvisited_input := false
		for input, i in n.inputs {
			if input == nil do continue
			if !worklist_contains(&wl, input) {
				append(&stack, input)
				unvisited_input = true
				break
			}
		}

		if unvisited_input do continue

		for input in n.inputs {
			if input == nil do continue
			print_node_name_gv(sb, n)
			fmt.sbprint(sb, "->")
			print_node_name_gv(sb, input)
			fmt.sbprintln(sb, ";")
		}

		pop(&stack)
	}

	return true
}

@(private = "file")
print_node_name_gv :: proc(sb: ^strings.Builder, n: ^Node) {
	fmt.sbprintf(sb, "{}{}", n.kind, n.gvn)
}
