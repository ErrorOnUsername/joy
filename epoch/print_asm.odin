package epoch

import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"

dump_module :: proc(mod: ^Module, out_path: string) -> bool {
	sb: strings.Builder
	defer strings.builder_destroy(&sb)

	for sym in mod.symbols {
		asm_symbol(sym, &sb) or_return
		fmt.sbprint(&sb, "\n")
	}

	err := os.write_entire_file_or_err(out_path, sb.buf[:])
	if err != nil {
		fmt.printfln("Failed to dump module '{}'. Reason: {}", mod.name, os.error_string(err))
		return false
	}

	return true
}

asm_symbol :: proc(sym: ^Symbol, sb: ^strings.Builder) -> bool {
	switch sym.linkage {
		case .Public:
			fmt.sbprint(sb, "extern ")
		case .Private:
			fmt.sbprint(sb, "internal ")
	}

	switch s in sym.derived {
		case ^Function:
			fmt.sbprintf(sb, "fn {}(", s.name)
			proto := s.proto
			param_count := len(proto.params)
			put_params_on_newlines := param_count > 2
			if put_params_on_newlines {
				fmt.sbprintf(sb, "\n")
			}
			for p in &proto.params {
				if put_params_on_newlines {
					fmt.sbprintf(sb, "\t")
				}
				fmt.sbprintf(sb, "{}: <type>", p.name)
			}
			if put_params_on_newlines {
				fmt.sbprintf(sb, "\n")
			}
			fmt.sbprintf(sb, ") {{\n")

			wl: Worklist
			worklist_init(&wl, s.node_count, context.allocator)
			defer worklist_deinit(&wl)

			asm_node(&wl, s.end, sb) or_return

			fmt.sbprintf(sb, "}}")
		case ^Global:
			fmt.sbprintf(sb, "const {} = [", s.name)
			for b, i in s.data {
				fmt.sbprintf(sb, "0x{:x}", b)
				if i < len(s.data) - 1 {
					fmt.sbprint(sb, ", ")
				}
			}
			fmt.sbprint(sb, "]")
	}

	return true
}

asm_node :: proc(w: ^Worklist, n: ^Node, sb: ^strings.Builder) -> bool {
	assert(n != nil)
	if worklist_contains(w, n) do return true

	worklist_push(w, n)

	for input, i in n.inputs {
		if input == nil && i == 0 do continue
		assert(input != nil)
		asm_node(w, input, sb) or_return
	}

	#partial switch n.kind {
		case .Start:
			fmt.sbprintf(sb, "#start\n")
		case .Region:
			name := n.extra.tag
			fmt.sbprintf(sb, "@{} ({} <- {}):\n", name, n.gvn, n.inputs[0].gvn)
		case .End:
			fmt.sbprintf(sb, "#end\n")
		case .Branch, .Goto, .MemSet, .Return, .Store:
			fmt.sbprintf(sb, "\t{} ", n.kind)
			for input, i in n.inputs {
				if i == 0 && input == nil {
					fmt.sbprintf(sb, "@nil")
				} else {
					fmt.sbprintf(sb, "%%{}", input.gvn)
				}
				if i < len(n.inputs) - 1 {
					fmt.sbprintf(sb, ", ")
				}
			}
			fmt.sbprintf(sb, "\n")
		case:
			fmt.sbprintf(sb, "\t%%{} := {} ", n.gvn, n.kind)
			for input, i in n.inputs {
				if i == 0 && input == nil {
					fmt.sbprintf(sb, "@nil")
				} else {
					fmt.sbprintf(sb, "%%{}", input.gvn)
				}
				if i < len(n.inputs) - 1 {
					fmt.sbprintf(sb, ", ")
				}
			}

			fmt.sbprintf(sb, "\n")

			for u in &n.users {
				asm_node(w, u.n, sb) or_return
			}
	}
	return true
}

