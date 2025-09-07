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
			assert(len(s.params) - 2 == len(proto.params))
			for p, i in &proto.params {
				if put_params_on_newlines {
					fmt.sbprintf(sb, "\t")
				}
				fmt.sbprintf(sb, "{} -> ", p.name)
				print_node_value(sb, s.params[i + 2])
			}
			if put_params_on_newlines {
				fmt.sbprintf(sb, "\n")
			}
			fmt.sbprintf(sb, ") {{\n")

			wl: Worklist
			worklist_init(&wl, s.node_count)
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
		if n.kind == .Region && i > 0 do continue // skip back-edges (loops)
		assert(input != nil)
		asm_node(w, input, sb) or_return
	}

	#partial switch n.kind {
		case .Start:
			fmt.sbprintf(sb, "#start\n")
		case .Region:
			name := n.extra.tag
			print_node_value(sb, n)
			fmt.sbprintf(sb, " <- (")
			for input, i in n.inputs {
				print_node_value(sb, input)
				if i != len(n.inputs) - 1 {
					fmt.sbprintf(sb, ", ")
				}
			}
			fmt.sbprintf(sb, "):\n")
		case .End:
			fmt.sbprintf(sb, "#end <- ")
			for input, i in n.inputs {
				print_node_value(sb, input)
				if i != len(n.inputs) - 1 {
					fmt.sbprintf(sb, ", ")
				}
			}
			fmt.sbprintf(sb, "\n")
		case:
			fmt.sbprintf(sb, "        {} ", n.kind)
			for input, i in n.inputs {
				if i == 0 do continue
				print_node_value(sb, input)
				if i < len(n.inputs) - 1 {
					fmt.sbprintf(sb, ", ")
				}
			}

			fmt.sbprintf(sb, " -> ")
			print_node_value(sb, n)

			if n.inputs[0] != nil {
				fmt.sbprintf(sb, "  [{}]", n.inputs[0].gvn)
			}

			fmt.sbprintf(sb, "\n")
	}

	for u in &n.users {
		if u.slot == 0 {
			asm_node(w, u.n, sb) or_return
		}
	}

	return true
}

@(private = "file")
print_node_value :: proc(sb: ^strings.Builder, n: ^Node) {
	if n == nil {
		fmt.sbprint(sb, "_")
		return
	}

	print_node_type(sb, n)

	fmt.sbprint(sb, " ")

	#partial switch n.kind {
		case .Region:
			assert(n.extra != nil)
			assert(len(n.extra.tag) > 0)
			fmt.sbprintf(sb, "@{}.{}", n.extra.tag, n.gvn)
		case .Local:
			assert(n.extra != nil)
			assert(len(n.extra.tag) > 0)
			fmt.sbprintf(sb, "l.{}.{}", n.extra.tag, n.gvn)
		case:
			fmt.sbprintf(sb, "v{}", n.gvn)
	}
}

@(private = "file")
print_node_type :: proc(sb: ^strings.Builder, n: ^Node) {
	switch n.type.kind {
		case .Control:
			fmt.sbprint(sb, "ctrl")
		case .Float:
			fmt.sbprintf(sb, "f{}", n.type.bitwidth)
		case .Int:
			fmt.sbprintf(sb, "i{}", n.type.bitwidth)
		case .Memory:
			fmt.sbprint(sb, "mem")
		case .Ptr:
			fmt.sbprint(sb, "ptr")
		case .Tuple:
			fmt.sbprint(sb, "tuple")
	}
}

