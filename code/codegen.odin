package main

import "../epoch"

cg_emit_stmnt :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	mod := ctx.checker.cg_module

	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
			#partial switch v in s.value.derived_expr {
				case ^ProcProto:
					dbg_type := cg_get_debug_type(s.type)
					proto := epoch.new_function_proto_from_debug_type(mod, dbg_type)
					fn := epoch.new_function(mod, s.name, proto)
					v.cg_val = &fn.symbol
			}
		case ^VarDecl:
			dbg := cg_get_debug_type(s.type)
			var := epoch.add_local(ctx.cg_fn, dbg.size, dbg.align)
			s.cg_val = var
			cg_emit_expr(ctx, s.default_value) or_return
			v := cg_get_node_val(s.default_value)
			is_volatile := false // TODO(rd): Hook this into the type system once this is expressable (necessary for embedded devices)
			epoch.insr_store(ctx.cg_fn, var, v, is_volatile)
		case ^EnumVariantDecl:
			unreachable()
		case ^UnionVariantDecl:
			unreachable()
		case ^ExprStmnt:
			cg_emit_expr(ctx, s.expr) or_return
			v := cg_get_node_val(s.expr)
			assert(epoch.ty_is_void(v.type))
			s.cg_val = s.expr.cg_val
		case ^ContinueStmnt:
			assert(ctx.curr_loop != nil)
			ctrl := cg_get_loop_ctrl(ctx, ctx.curr_loop)
			epoch.insr_br(ctx.cg_fn, ctrl)
		case ^BreakStmnt:
			assert(ctx.curr_loop != nil)
			ctrl := cg_get_loop_exit_ctrl(ctx, ctx.curr_loop)
			epoch.insr_br(ctx.cg_fn, ctrl)
		case ^ReturnStmnt:
			cg_emit_expr(ctx, s.expr) or_return
			v := cg_get_node_val(s.expr)
			epoch.insr_ret(ctx.cg_fn, v)
	}

	log_spanned_error(&stmnt.span, "impl cg_emit_stmnt")
	return false
}

cg_get_node_val :: proc(n: ^Node) -> ^epoch.Node {
	n, is_n := n.cg_val.(^epoch.Node)
	assert(is_n)
	return n
}

cg_get_debug_type :: proc(t: ^Type) -> ^epoch.DebugType {
}

cg_get_loop_exit_ctrl :: proc(ctx: ^CheckerContext, l: ^Expr) -> ^epoch.Node {
}

cg_get_loop_ctrl :: proc(ctx: ^CheckerContext, l: ^Expr) -> ^epoch.Node {
}

cg_emit_expr :: proc(ctx: ^CheckerContext, expr: ^Expr) -> bool {
	switch e in expr.derived_expr {
		case ^ProcProto:
			unreachable()
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

