package main


cg_emit_stmnt :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	switch g_cl_state.backend {
		case .C:
			cg_emit_stmnt_c99(ctx, stmnt) or_return
		case .Opto:
			cg_emit_stmnt_opto(ctx, stmnt) or_return
	}
	return true
}

