package epoch


run_passes :: proc(ctx: ^EpochContext) -> bool {
	// TODO(RD): multi-thread this, with the thread pool so that the main compiler
	//           can pump this and make it go wide (think pick_up_work)
	mod_head := ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		dump_module(mod, "asm.epoch") or_return
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Function:
					opto_function(ctx, s) or_return
					codegen_function(ctx, s) or_return
			}
		}
		mod_head = mod_head.next
	}

	link_program(ctx) or_return

	return true
}

