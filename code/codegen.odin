package main

import "../epoch"

cg_emit_stmnt :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
		case ^VarDecl:
			var := epoch.add_local()
			s.cg_val = var
			cg_emit_expr(ctx, s.default_value) or_return
			epoch.insr_store()
		case ^EnumVariantDecl:
			unreachable()
		case ^UnionVariantDecl:
			unreachable()
		case ^ExprStmnt:
			cg_emit_expr(ctx, s.expr) or_return
			assert(epoch.ty_is_void(s.expr.cg_val.type))
		case ^ContinueStmnt:
			assert(ctx.curr_loop != nil)
			ctrl := cg_get_loop_ctrl(ctx.curr_loop)
			epoch.insr_br()
		case ^BreakStmnt:
			assert(ctx.curr_loop != nil)
			ctrl := cg_get_loop_exit_ctrl(ctx.curr_loop)
			epoch.insr_br()
		case ^ReturnStmnt:
			val := cg_emit_expr(ctx, s.expr)
			epoch.insr_ret()
	}

	log_spanned_error(&stmnt.span, "impl cg_emit_stmnt")
	return false
}

cg_get_loop_ctrl :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> ^epoch.Node {
}

cg_emit_expr :: proc(ctx: ^CheckerContext, expr: ^Expr) -> bool {
	switch e in expr.derived_expr {
		case ^ProcProto:
		case ^Ident:
		case ^StringLiteralExpr:
		case ^NumberLiteralExpr:
		case ^NamedStructLiteralExpr:
		case ^AnonStructLiteralExpr:
		case ^MemberAccessExpr:
		case ^ImplicitSelectorExpr:
		case ^Scope:
		case ^IfExpr:
		case ^ForLoop:
		case ^WhileLoop:
		case ^InfiniteLoop:
		case ^RangeExpr:
		case ^UnaryOpExpr:
		case ^BinOpExpr:
		case ^ProcCallExpr:
		case ^PrimitiveTypeExpr:
		case ^PointerTypeExpr:
		case ^SliceTypeExpr:
		case ^ArrayTypeExpr:
	}

	log_error( "impl cg_emit_expr" )
	return false
}

