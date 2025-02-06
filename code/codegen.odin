package main

import "../epoch"

cg_emit_stmnt :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	mod := ctx.checker.cg_module

	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
			#partial switch v in s.value.derived_expr {
				case ^ProcProto:
					dbg := cg_get_debug_type(v.type)
					proto := epoch.new_function_proto_from_debug_type(mod, dbg)
					fn := epoch.new_function(mod, s.name, proto)
					v.cg_val = &fn.symbol
				case:
					cg_emit_expr(ctx, s.value)
			}
		case ^VarDecl:
			fn := ctx.cg_fn
			assert(fn != nil)

			dbg := cg_get_debug_type(s.type)
			var := epoch.add_local(ctx.cg_fn, dbg.size, dbg.align)
			s.cg_val = var

			if s.default_value != nil {
				cg_emit_expr(ctx, s.default_value) or_return
				v := cg_get_node_val(s.default_value)
				is_volatile := false // TODO(rd): Hook this into the type system once this is expressable (necessary for embedded devices)
				epoch.insr_store(fn, var, v, is_volatile)
			} else {
				v := epoch.new_int_const(fn, epoch.TY_I8, u64(0))
				sz := epoch.new_int_const(fn, epoch.TY_I64, i64(dbg.size))
				epoch.insr_memset(fn, var, v, sz)
			}
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

	return true
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
			assert(!ty_is_typeid(e.type))
			decl := lookup_ident(ctx, e.name)
			#partial switch d in decl.derived_stmnt {
				case ^ConstDecl:
					// For consts we want the actual value since they don't have
					// actual symbols in the binary (except for functions)
					assert(d.value)
					e.cg_val = d.value.cg_val
				case ^VarDecl:
					// For vars we want the pointer to the stack slot
					e.cg_val = d.cg_val
				case:
					unreachable() // there isn't a way to address anything else by name so just crash ig. This would be a bug in the typecheker otherwise
			}
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

	log_spanned_error(&expr.span, "impl cg_emit_expr")
	return false
}

