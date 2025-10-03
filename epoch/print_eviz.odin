package epoch

import "core:fmt"
import "core:os"
import "core:strings"


dump_module_eviz :: proc(mod: ^Module, out_path: string) -> bool {
	sb: strings.Builder
	defer strings.builder_destroy(&sb)

	fmt.sbprintfln(&sb, "{}.pre_opto = module {{", mod.name)

	for sym in mod.symbols {
		switch s in sym.derived {
			case ^Function: print_fn(&sb, s) or_return
			case ^Global:   print_global(&sb, s) or_return
		}
	}

	fmt.sbprintln(&sb, "};")

	path_name: strings.Builder
	defer strings.builder_destroy(&sb)

	path := fmt.sbprintf(&path_name, "{}.eviz", mod.name)
	err := os.write_entire_file_or_err(path, sb.buf[:])
	if err != nil {
		fmt.printfln("Failed to dump module '{}' to path '{}'. Reason: {}", mod.name, path, os.error_string(err))
		return false
	}

	return true
}

@(private = "file")
print_fn :: proc(sb: ^strings.Builder, fn: ^Function) -> bool {
	fmt.sbprintfln(sb, "\t{} = fn_graph {{", fn.name)

	visited: Worklist
	worklist_init(&visited, fn.node_count)
	defer worklist_deinit(&visited)

	stack: [dynamic]^Node
	defer delete(stack)

	append(&stack, fn.end)

	for len(stack) > 0 {
		n := stack[len(stack) - 1]

		worklist_push(&visited, n)

		unvisited_input := false
		for input in n.inputs {
			if input == nil do continue
			if !worklist_contains(&visited, input) {
				unvisited_input = true
				append(&stack, input)
				break
			}
		}
		if unvisited_input do continue

		print_node(sb, n)

		pop(&stack)
	}

	fmt.sbprintln(sb, "\t};")
	return true
}

@(private = "file")
print_node :: proc(sb: ^strings.Builder, n: ^Node) {
	fmt.sbprint(sb, "\t\t")
	print_node_name(sb, n)
	fmt.sbprint(sb, " = ")

	switch n.kind {
		case .Start:
			fmt.sbprint(sb, "$start")
		case .End:
			fmt.sbprint(sb, "$end { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; }")
		case .Region:
			fmt.sbprint(sb, "region { ")
			for input, i in n.inputs {
				fmt.sbprintf(sb, "pred{} = ", i)
				print_node_name(sb, input)
				fmt.sbprint(sb, "; ")
			}
			fmt.sbprint(sb, "}")
		case .Proj:
			fmt.sbprint(sb, "proj { src = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprintf(sb, "; idx = {}; ", n.extra.derived.(^ProjExtra).idx)
			fmt.sbprint(sb, "}")
		case .IntConst:
			fmt.sbprint(sb, "$int")
		case .F32Const:
			fmt.sbprint(sb, "$f32")
		case .F64Const:
			fmt.sbprint(sb, "$f64")
		case .Local:
			extra := n.extra.derived.(^LocalExtra)
			fmt.sbprintf(sb, "$local {{ size = {}; align = {}; }}", extra.size, extra.align)
		case .Symbol:
			fmt.sbprintf(sb, "$symbol {{ name = {} }}", n.extra.derived.(^SymbolExtra).sym.name)
		case .Return:
			fmt.sbprint(sb, "ret { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; val = ")
			e: ^Node
			if len(n.inputs) == 3 {
				e = n.inputs[2]
			}
			print_node_name(sb, e)
			fmt.sbprint(sb, "; }")
		case .Call:
			fmt.sbprint(sb, "call { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; target = ")
			print_node_name(sb, n.inputs[2])

			for i in 0..<(len(n.inputs) - 3) {
				fmt.sbprintf(sb, "; param{} = ", i)
				print_node_name(sb, n.inputs[3 + i])
			}

			fmt.sbprint(sb, "; }")
		case .Branch:
			fmt.sbprint(sb, "br { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; cond = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; then = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; else = ")
			print_node_name(sb, n.inputs[3])
			fmt.sbprint(sb, "; }")
		case .Goto:
			fmt.sbprint(sb, "goto { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; target = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; }")
		case .Phi:
			fmt.sbprint(sb, "phi")
		case .Load:
			fmt.sbprint(sb, "load { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; addr = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Store:
			fmt.sbprint(sb, "store { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; addr = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; val = ")
			print_node_name(sb, n.inputs[3])
			fmt.sbprint(sb, "; }")
		case .MemCpy:
			fmt.sbprint(sb, "memcpy { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; dst = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; src = ")
			print_node_name(sb, n.inputs[3])
			fmt.sbprint(sb, "; count = ")
			print_node_name(sb, n.inputs[4])
			fmt.sbprint(sb, "; }")
		case .MemSet:
			fmt.sbprint(sb, "memcpy { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; dst = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; val = ")
			print_node_name(sb, n.inputs[3])
			fmt.sbprint(sb, "; count = ")
			print_node_name(sb, n.inputs[4])
			fmt.sbprint(sb, "; }")
		case .VolatileRead:
			fmt.sbprint(sb, "vload { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; addr = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .VolatileWrite:
			fmt.sbprint(sb, "vstore { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; mem = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; addr = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; val = ")
			print_node_name(sb, n.inputs[3])
			fmt.sbprint(sb, "; }")
		case .GetMemberPtr:
			fmt.sbprint(sb, "getmemberptr { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; base = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; offset = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .And:
			fmt.sbprint(sb, "and { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Or:
			fmt.sbprint(sb, "or { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .XOr:
			fmt.sbprint(sb, "xor { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Add:
			fmt.sbprint(sb, "add { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Sub:
			fmt.sbprint(sb, "sub { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Mul:
			fmt.sbprint(sb, "mul { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Shl:
			fmt.sbprint(sb, "shl { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Shr:
			fmt.sbprint(sb, "shr { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Sar:
			fmt.sbprint(sb, "sar { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Rol:
			fmt.sbprint(sb, "rol { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Ror:
			fmt.sbprint(sb, "ror { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .UDiv:
			fmt.sbprint(sb, "udiv { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .SDiv:
			fmt.sbprint(sb, "sdiv { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .UMod:
			fmt.sbprint(sb, "umod { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .SMod:
			fmt.sbprint(sb, "smod { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FAdd:
			fmt.sbprint(sb, "fadd { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FSub:
			fmt.sbprint(sb, "fsub { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FMul:
			fmt.sbprint(sb, "fmul { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FDiv:
			fmt.sbprint(sb, "fdiv { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FMax:
			fmt.sbprint(sb, "fmax { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .FMin:
			fmt.sbprint(sb, "fmin { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpEq:
			fmt.sbprint(sb, "cmp.eq { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpNeq:
			fmt.sbprint(sb, "cmp.neq { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpULt:
			fmt.sbprint(sb, "cmp.ult { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpULe:
			fmt.sbprint(sb, "cmp.ule { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpSLt:
			fmt.sbprint(sb, "cmp.slt { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpSLe:
			fmt.sbprint(sb, "cmp.sle { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpFLt:
			fmt.sbprint(sb, "cmp.flt { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .CmpFLe:
			fmt.sbprint(sb, "cmp.fle { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; lhs = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; rhs = ")
			print_node_name(sb, n.inputs[2])
			fmt.sbprint(sb, "; }")
		case .Not:
			fmt.sbprint(sb, "not { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; rand = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; }")
		case .Negate:
			fmt.sbprint(sb, "neg { pred = ")
			print_node_name(sb, n.inputs[0])
			fmt.sbprint(sb, "; rand = ")
			print_node_name(sb, n.inputs[1])
			fmt.sbprint(sb, "; }")
	}

	fmt.sbprintln(sb, ";")
}

@(private = "file")
print_node_name :: proc(sb: ^strings.Builder, n: ^Node) {
	if n == nil {
		fmt.sbprintf(sb, "null")
		return
	}

	if n.extra != nil && len(n.extra.tag) > 0 {
		fmt.sbprintf(sb, "{}.", n.extra.tag)
	}
	fmt.sbprintf(sb, "{}", n.gvn)
}

@(private = "file")
print_global :: proc(sb: ^strings.Builder, g: ^Global) -> bool {
	fmt.sbprintfln(sb, "\t{} = global {{ data = {}; }};", g.name, g.data)
	return true
}

