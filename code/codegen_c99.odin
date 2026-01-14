package main

import "core:strings"


cg_emit_stmnt_c99 :: proc(ctx: ^CheckerContext, stmnt: ^Stmnt) -> bool {
	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
			#partial switch v in s.value.derived_expr {
				case ^ProcProto:
					dbg := cg_get_debug_type(mod, v.type, &v.span) or_return
					proto := opto.new_function_proto_from_debug_type(mod, dbg)
					fn := opto.new_function(mod, s.name, proto)
					v.cg_val = opto.add_sym(fn, &fn.symbol)

					last_fn := ctx.cg_fn
					defer ctx.cg_fn = last_fn
					ctx.cg_fn = fn

					for p in v.params {
						cg_emit_stmnt(ctx, p) or_return
					}
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
			var := opto.add_local(ctx.cg_fn, s.name, s.type.size, s.type.alignment)
			s.cg_val = var

			// FIXME(RD): Params are just zeroed out by default. that's dumb as shit
			if s.default_value != nil {
				v := cg_emit_expr(ctx, s.default_value) or_return
				is_volatile := false // TODO(rd): Hook this into the type system once this is expressable (necessary for embedded devices)
				opto.insr_store(fn, var, v, is_volatile)
			} else {
				v := opto.new_int_const(fn, opto.TY_I8, u64(0))
				sz := opto.new_int_const(fn, opto.TY_I64, i64(s.type.size))
				opto.insr_memset(fn, var, v, sz)
			}
		case ^EnumVariantDecl:
			log_spanned_error(&s.span, "Internal Compiler Error: Got unexpected enum variant in cg_emit_expr (this should only be read in cg_get_debug_type)")
			return false
		case ^UnionVariantDecl:
			log_spanned_error(&s.span, "Internal Compiler Error: Got unexpected union variant in cg_emit_expr (this should only be read in cg_get_debug_type)")
			return false
		case ^ExprStmnt:
			v := cg_emit_expr(ctx, s.expr) or_return
			if v != nil {
				log_spanned_errorf(&s.span, "Internal Compiler Error: Expression produces a value of type '{}' but that value isn't captured", s.expr.type.name)
				return false
			}
			s.cg_val = s.expr.cg_val
		case ^ContinueStmnt:
			if ctx.curr_loop == nil {
				log_spanned_error(&s.span, "Internal Compiler Error: codegen recieved a continue statement outside of a loop")
				return false
			}

			if ctx.cg_loop_start == nil {
				log_spanned_error(&s.span, "Internal Compiler Error: codegen recieved a continue statement but 'cg_loop_start' wasn't set")
				return false
			}

			fn := ctx.cg_fn
			assert(fn != nil)

			opto.insr_goto(fn, ctx.cg_loop_start)
		case ^BreakStmnt:
			if ctx.curr_loop == nil {
				log_spanned_error(&s.span, "Internal Compiler Error: codegen recieved a break statement outside of a loop")
				return false
			}

			if ctx.cg_loop_end == nil {
				log_spanned_error(&s.span, "Internal Compiler Error: codegen recieved a break statement but 'cg_loop_end' wasn't set")
				return false
			}

			fn := ctx.cg_fn
			assert(fn != nil)

			opto.insr_goto(fn, ctx.cg_loop_end)
		case ^ReturnStmnt:
			if s.expr != nil {
				v := cg_emit_expr(ctx, s.expr) or_return
				opto.insr_ret(ctx.cg_fn, v)
			} else {
				opto.insr_ret(ctx.cg_fn, nil)
			}
	}
}

