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

