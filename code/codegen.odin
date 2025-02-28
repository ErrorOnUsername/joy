package main

import "../epoch"

import "core:sync"

cg_emit_stmnt :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	mod := ctx.checker.cg_module

	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
			#partial switch v in s.value.derived_expr {
				case ^ProcProto:
					dbg := cg_get_debug_type(mod, v.type, &v.span) or_return
					proto := epoch.new_function_proto_from_debug_type(mod, dbg)
					fn := epoch.new_function(mod, s.name, proto)
					v.cg_val = &fn.symbol
				case ^Scope:
					assert(v.variant != .File && v.variant != .Logic)
					_ = cg_get_debug_type(mod, v.type, &v.span) or_return
				case:
					cg_emit_expr(ctx, s.value) or_return
			}
		case ^VarDecl:
			fn := ctx.cg_fn
			assert(fn != nil)

			dbg := cg_get_debug_type(mod, s.type, &s.span) or_return
			var := epoch.add_local(ctx.cg_fn, s.type.size, s.type.alignment)
			s.cg_val = var

			if s.default_value != nil {
				cg_emit_expr(ctx, s.default_value) or_return
				v := cg_get_node_val(s.default_value)
				is_volatile := false // TODO(rd): Hook this into the type system once this is expressable (necessary for embedded devices)
				epoch.insr_store(fn, var, v, is_volatile)
			} else {
				v := epoch.new_int_const(fn, epoch.TY_I8, u64(0))
				sz := epoch.new_int_const(fn, epoch.TY_I64, i64(s.type.size))
				epoch.insr_memset(fn, var, v, sz)
			}
		case ^EnumVariantDecl:
			log_spanned_error(&s.span, "Internal Compiler Error: Got unexpected enum variant in cg_emit_expr (this should only be read in cg_get_debug_type)")
			return false
		case ^UnionVariantDecl:
			log_spanned_error(&s.span, "Internal Compiler Error: Got unexpected union variant in cg_emit_expr (this should only be read in cg_get_debug_type)")
			return false
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

cg_get_debug_type :: proc(mod: ^epoch.Module, t: ^Type, span: ^Span) -> (dbg: ^epoch.DebugType, ok: bool) {
	sync.recursive_mutex_lock(&t.debug_type_mtx)
	defer sync.recursive_mutex_unlock(&t.debug_type_mtx)

	if t.debug_type != nil {
		return t.debug_type, true
	}

	switch ty in t.derived {
		case ^PointerType:
			base_type := cg_get_debug_type(mod, ty.underlying, span) or_return
			d := epoch.new_debug_type_ptr(mod, base_type)

			dbg = d
		case ^SliceType:
			d := epoch.new_debug_type_struct(mod, ty.name, 2, ty.size, ty.alignment)

			underlying_dbg := cg_get_debug_type(mod, ty.underlying, span) or_return
			data_ptr_dbg := epoch.new_debug_type_ptr(mod, underlying_dbg)
			d.fields[0] = epoch.new_debug_type_field(mod, "data", data_ptr_dbg, 0)

			count_dbg := cg_get_debug_type(mod, ty_builtin_usize, span) or_return
			d.fields[1] = epoch.new_debug_type_field(mod, "count", count_dbg, ty_builtin_usize.size)

			dbg = d
		case ^PrimitiveType:
			switch ty.kind {
				case .Void:
					dbg = epoch.dbg_ty_void
				case .Bool:
					dbg = epoch.dbg_ty_bool
				case .U8, .U16, .U32, .U64, .USize:
					dbg = epoch.get_int_debug_type(ty.size * 8, false)
				case .I8, .I16, .I32, .I64, .ISize:
					dbg = epoch.get_int_debug_type(ty.size * 8, true)
				case .F32:
					dbg = epoch.dbg_ty_f32
				case .F64:
					dbg = epoch.dbg_ty_f64
				case .String:
					d := epoch.new_debug_type_struct(mod, "string", 2, ty.size, ty.alignment)

					underlying_dbg := cg_get_debug_type(mod, ty_builtin_u8, span) or_return
					data_ptr_dbg := epoch.new_debug_type_ptr(mod, underlying_dbg)
					d.fields[0] = epoch.new_debug_type_field(mod, "data", data_ptr_dbg, 0)

					count_dbg := cg_get_debug_type(mod, ty_builtin_usize, span) or_return
					d.fields[1] = epoch.new_debug_type_field(mod, "count", count_dbg, ty_builtin_usize.size)

					dbg = d
				case .CString:
					underlying_dbg := cg_get_debug_type(mod, ty_builtin_u8, span) or_return
					dbg = epoch.new_debug_type_ptr(mod, underlying_dbg)
				case .RawPtr:
					underlying_dbg := cg_get_debug_type(mod, ty_builtin_void, span) or_return
					dbg = epoch.new_debug_type_ptr(mod, underlying_dbg)
				case .Range:
					d := epoch.new_debug_type_struct(mod, "range", 2, ty.size, ty.alignment)
					range_bound_dbg := cg_get_debug_type(mod, ty_builtin_isize, span) or_return
					d.fields[0] = epoch.new_debug_type_field(mod, "start", range_bound_dbg, ty_builtin_isize.size)
					d.fields[1] = epoch.new_debug_type_field(mod, "end", range_bound_dbg, ty_builtin_isize.size * 2)
					dbg = d
				case .UntypedInt, .UntypedString:
					log_spanned_errorf(span, "Internal Compiler Error: got unexpected '{}' expression after typechecking is complete", ty.name )
					return nil, false
				case .TypeID:
					log_spanned_error(span, "Internal Compiler Error: got unexpected typeid expression after typechecking is complete")
					return nil, false
			}
		case ^StructType:
			d := epoch.new_debug_type_struct(mod, ty.name, len(ty.members), ty.size, ty.alignment)
			for mem, i in ty.members {
				mem_dbg := cg_get_debug_type(mod, mem.ty, span) or_return
				d.fields[i] = epoch.new_debug_type_field(mod, mem.name, mem_dbg, mem.offset)
			}
			dbg = d
		case ^EnumType:
			dbg = epoch.get_int_debug_type(ty.size * 8, false)
		case ^UnionType:
			d := epoch.new_debug_type_union(mod, ty.name, len(ty.variants), ty.size, ty.alignment)
			for v, i in ty.variants {
				var_dbg := cg_get_debug_type(mod, v, span) or_return
				v_dbg, is_struct := var_dbg.extra.(^epoch.DebugTypeStruct)
				assert(is_struct)
				d.variants[i] = v_dbg
			}
			dbg = d
		case ^FnType:
			has_returns := ty.return_type != nil && !ty_is_void(ty.return_type)
			return_count := 1 if has_returns else 0
			d := epoch.new_debug_type_fn(mod, ty.name, len(ty.params), return_count)
			for p, i in ty.params {
				p_dbg := cg_get_debug_type(mod, p, span) or_return
				d.params[i] = epoch.new_debug_type_field(mod, p.name, p_dbg, 0)
			}
			if has_returns {
				d.returns[0] = cg_get_debug_type(mod, ty.return_type, span) or_return
			}
			dbg = d
	}
	return dbg, true
}

cg_get_loop_exit_ctrl :: proc(ctx: ^CheckerContext, l: ^Expr) -> ^epoch.Node {
	assert(ctx.loop_body != nil && ctx.loop_exit != nil)
	return ctx.loop_exit
}

cg_get_loop_ctrl :: proc(ctx: ^CheckerContext, l: ^Expr) -> ^epoch.Node {
	assert(ctx.loop_body != nil && ctx.loop_exit != nil)
	return ctx.loop_body
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
					assert(d.value != nil)
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

