package main

import "../epoch"

import "core:fmt"
import "core:hash"
import "core:math/big"
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
					v.cg_val = epoch.add_sym(fn, &fn.symbol)

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
			var := epoch.add_local(ctx.cg_fn, s.type.size, s.type.alignment)
			s.cg_val = var

			// FIXME(RD): Params are just zeroed out by default. that's dumb as shit
			if s.default_value != nil {
				v := cg_emit_expr(ctx, s.default_value) or_return
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

			epoch.insr_goto(fn, ctx.cg_loop_start)
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

			epoch.insr_goto(fn, ctx.cg_loop_end)
		case ^ReturnStmnt:
			v := cg_emit_expr(ctx, s.expr) or_return
			epoch.insr_ret(ctx.cg_fn, v)
	}

	return true
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
		case ^ArrayType:
			underlying_dbg := cg_get_debug_type(mod, ty.underlying, span) or_return
			d := epoch.new_debug_type_array(mod, underlying_dbg, ty.count)

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
				case .UntypedInt, .UntypedFloat, .UntypedString:
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
			d := epoch.new_debug_type_enum(mod, ty.name, len(ty.variants), ty.underlying.size, ty.underlying.alignment)
			for var, i in &ty.variants {
				d.variants[i].name = var.name
				d.variants[i].value = var.value
			}
			dbg = d
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
			for p, i in &ty.params {
				p_dbg := cg_get_debug_type(mod, p.ty, span) or_return
				d.params[i] = epoch.new_debug_type_field(mod, p.name, p_dbg, 0)
			}
			if has_returns {
				d.returns[0] = cg_get_debug_type(mod, ty.return_type, span) or_return
			}
			dbg = d
	}
	return dbg, true
}

cg_emit_expr :: proc(ctx: ^CheckerContext, expr: ^Expr) -> (ret: ^epoch.Node, ok: bool) {
	switch e in expr.derived_expr {
		case ^ProcProto:
			log_spanned_error(&e.span, "Internal Compiler Error: encountered proc proto during expr emit. Get dat closure out this bitch")
			return nil, false
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
					v := d.cg_val
					if v == nil {
						log_spanned_errorf( &e.span, "Internal Compiler Error: variable '{}' is used before its value has been codegen'd", e.name )
						return nil, false
					}
					e.cg_val = v
				case:
					log_spanned_error(&e.span, "Internal Compiler Error: Ident doesn't reference a var or const.")
					return nil, false
			}

			return e.cg_val, true
		case ^StringLiteralExpr:
			mod := ctx.checker.cg_module
			hash := hash.crc32(e.val)

			sync.lock(&mod.allocator_lock)
			literal_name := fmt.aprintf("str${}", hash, allocator = mod.allocator)
			sync.unlock(&mod.allocator_lock)

			// FIXME: Deduplicate these since otherwise we'll get duplicate symbol errors
			g := epoch.new_global(mod, literal_name, .Private)
			epoch.global_set_data(mod, g, e.val)

			n := epoch.add_sym(ctx.cg_fn, g)
			e.cg_val = n

			return n, true
		case ^NumberLiteralExpr:
			if ty_is_untyped_builtin(e.type) {
				log_spanned_error(&e.span, "Internal Compiler Error: Number literal is still untyped")
				return nil, false
			}

			mod := ctx.checker.cg_module
			fn := ctx.cg_fn
			assert(fn != nil)

			d_type, ok := cg_get_debug_type(mod, e.type, &e.span)
			if !ok do return nil, false

			reg_class := epoch.get_debug_type_register_class(d_type)
			t := epoch.get_type_with_register_class(reg_class, d_type)

			switch &v in e.val {
				case big.Int:
					if !epoch.debug_type_is_int(d_type) {
						log_spanned_errorf(&e.span, "Internal Compiler Error: codegen found an integer literal with a non-integer debug type '{}'", e.type.name)
						return nil, false
					}

					ty_bit_count := epoch.debug_type_get_int_bit_count(d_type)
					literal_bit_count, bit_err := big.count_bits(&v)
					assert(bit_err == .Okay)

					// FIXME(RD): This should be handled in the typechecker itself when we figure out what type a literal should be, not this late
					if literal_bit_count > ty_bit_count {
						log_spanned_errorf(&e.span, "Internal Compiler Error: codegen found a literal that is to big ({} bits) for the specified type '{}'", literal_bit_count, e.type.name)
						return nil, false
					}

					assert(literal_bit_count < 64)
					val, get_err := big.get_u64(&v)
					assert(get_err == .Okay)

					n := epoch.new_int_const(fn, t, val)
					e.cg_val = n
					return n, true
				case f64:
					n := epoch.new_float_const(fn, t, v)
					e.cg_val = n
					return n, true
			}

			log_spanned_errorf(&e.span, "Internal Compiler Error: Invalid number literal of type '{}' reached codegen stage", e.type.name)
			return nil, false
		case ^NamedStructLiteralExpr:
		case ^AnonStructLiteralExpr:
			fn := ctx.cg_fn
			assert(fn != nil) // Again... this needs to be fixed for globals

			mod := ctx.checker.cg_module
			assert(mod != nil)

			lit_slot := epoch.add_local(fn, e.type.size, e.type.alignment)

			dbg_type := cg_get_debug_type(mod, e.type, &e.span) or_return

			if ty_is_struct(e.type) {
				checker_struct_ty, is_checker_struct := e.type.derived.(^StructType)
				assert(is_checker_struct)

				cg_struct_ty, is_cg_struct := dbg_type.extra.(^epoch.DebugTypeStruct)
				assert(is_cg_struct)

				assert(len(checker_struct_ty.members) == len(cg_struct_ty.fields))

				if len(e.vals) != len(checker_struct_ty.members) {
					log_spanned_errorf(&e.span, "Internal Compiler Error: codegen recieved an invalid struct literal. {} has {} fields, but the expression only has {} values", e.type.name, len(checker_struct_ty.members), len(e.vals))
					return nil, false
				}

				for v, i in e.vals {
					member_name := checker_struct_ty.members[i].name
					member_type := checker_struct_ty.members[i].ty
					if !ty_eq(v.type, member_type) {
						log_spanned_errorf(&v.span, "Internal Compiler Error: codegen recieved a malformed struct literal. Field '{}' has type '{}' but expression is of type '{}'", member_name, member_type.name, v.type.name)
						return nil, false
					}

					val := cg_emit_expr(ctx, v) or_return

					mem_ptr := epoch.insr_getmemberptr(fn, lit_slot, dbg_type, member_name)
					epoch.insr_store(fn, mem_ptr, val, false)
				}
			} else if ty_is_union(e.type) {
				cg_union_ty, is_cg_union := dbg_type.extra.(^epoch.DebugTypeUnion)
				assert(is_cg_union)
				log_spanned_error(&e.span, "impl union literals")
				return nil, false
			} else {
				log_spanned_errorf(&e.span, "Internal Compiler Error: codegen recieved a struct literal of type {} which is not a struct or union", e.type.name)
				return nil, false
			}

			e.cg_val = lit_slot

			return lit_slot, true
		case ^MemberAccessExpr:
			fn := ctx.cg_fn
			assert(fn != nil)

			mod := ctx.checker.cg_module
			assert(mod != nil)

			val := e.val
			val_base_type := ty_get_base(val.type)

			if ty_is_struct(val_base_type) {
				dbg_ty := cg_get_debug_type(mod, val_base_type, &val.span) or_return

				base := cg_emit_expr(ctx, val) or_return
				if ty_is_pointer(val.type) { // auto deref :D
					base = epoch.insr_load(fn, epoch.TY_PTR, base, false)
				}

				field := e.member
				// This logic is utterly IQ defficient. Just make a function dumbass
				for field != nil {
					#partial switch f in field.derived_expr {
						case ^MemberAccessExpr:
							#partial switch ff in f.val.derived_expr {
								case ^Ident:
									base = epoch.insr_getmemberptr(fn, base, dbg_ty, ff.name)
								case:
									log_spanned_error(&field.span, "Internal Compiler Error: codegen recived an invalid member access expression. Field is not an identifier or other member")
							}
							field = f.member
						case ^Ident:
							base = epoch.insr_getmemberptr(fn, base, dbg_ty, f.name)
							field = nil
						case:
							log_spanned_error(&field.span, "Internal Compiler Error: codegen recived an invalid member access expression. Field is not an identifier or other member")
					}
				}

				e.cg_val = base
			} else {
				log_spanned_errorf(&e.span, "codegen: impl member access on non-struct type '{}'", val.type.name)
				return nil, false
			}

			return e.cg_val, true
		case ^ImplicitSelectorExpr:
			fn := ctx.cg_fn
			assert(fn != nil) // FIXME: globals

			mod := ctx.checker.cg_module
			assert(mod != nil)

			if ty_is_enum(e.type) {
				dbg_type := cg_get_debug_type(mod, e.type, &e.span) or_return
				ident, is_ident := e.member.derived_expr.(^Ident)
				assert(is_ident)

				checker_enum_type, is_checker_enum := e.type.derived.(^EnumType)
				assert(is_checker_enum)

				cg_enum_type, is_cg_enum := dbg_type.extra.(^epoch.DebugTypeEnum)
				assert(is_cg_enum)

				found := false
				enum_val: u64
				for var in cg_enum_type.variants {
					if ident.name == var.name {
						found = true
						enum_val = var.value
						break
					}
				}
				assert(found)

				underlying_dbg_type := cg_get_debug_type(mod, checker_enum_type.underlying, &e.span) or_return

				reg_class := epoch.get_debug_type_register_class(underlying_dbg_type)
				t := epoch.get_type_with_register_class(reg_class, underlying_dbg_type)

				n := epoch.new_int_const(fn, t, enum_val)
				e.cg_val = n
			} else if ty_is_union(e.type) {
				log_spanned_error(&e.span, "impl union struct literals")
				return nil, false
			} else {
				log_spanned_errorf(&e.span, "Internal Compiler Error: codegen recieved an implicit selector expression of type '{}' that isn't an enum or a union", e.type.name)
				return nil, false
			}

			return e.cg_val, true
		case ^Scope:
			fn := ctx.cg_fn
			assert(fn != nil)

			fnl_v: ^epoch.Node
			if !ty_is_void(e.type) && e.cg_val == nil {
				fnl_v = epoch.add_local(fn, e.type.size, e.type.alignment)
				e.cg_val = fnl_v
			}

			old_scope := ctx.curr_scope
			defer ctx.curr_scope = old_scope
			ctx.curr_scope = e

			for s in e.stmnts {
				cg_emit_stmnt(ctx, s) or_return
			}

			return fnl_v, true
		case ^IfExpr:
			fn := ctx.cg_fn
			assert(fn != nil)

			dst_slot: ^epoch.Node
			if !ty_is_void(e.type) {
				dst_slot = epoch.add_local(fn, e.type.size, e.type.alignment)
				e.cg_val = dst_slot
			}

			end := epoch.new_region(fn, "if.end")

			curr_if := e
			for curr_if != nil {
				if curr_if.cond != nil {
					then := epoch.new_region(fn, "if.then")
					else_br := end

					if curr_if.else_block != nil {
						else_br = epoch.new_region(fn, "if.else")
					}

					true_val := epoch.new_int_const(fn, epoch.TY_BOOL, i64(1))
					cond_v := cg_emit_expr(ctx, e.cond) or_return
					cmp := epoch.insr_cmp_eq(fn, cond_v, true_val)

					epoch.insr_br(fn, cmp, then, else_br)
					epoch.set_control(fn, then)
				}

				// child sopes of the main if expr just inherit the main stack slot
				// so they store the result in the same spot.
				curr_if.then.cg_val = dst_slot // could be nil (if block doesn't yeild a value)
				br_v := cg_emit_expr(ctx, curr_if.then) or_return

				curr_if = curr_if.else_block
			}

			epoch.set_control(fn, end)
			return dst_slot, true
		case ^ForLoop:
			fn := ctx.cg_fn
			assert(fn != nil)

			mod := ctx.checker.cg_module
			assert(mod != nil)

			dst_slot: ^epoch.Node
			if !ty_is_void(e.type) {
				dst_slot = epoch.add_local(fn, e.type.size, e.type.alignment)
				e.cg_val = dst_slot
			}

			iter_slot := epoch.add_local(fn, e.iter.type.size, e.iter.type.alignment)

			loop_end := epoch.new_region(fn, "loop.end")
			last_end := ctx.cg_loop_end
			defer ctx.cg_loop_end = last_end
			ctx.cg_loop_end = loop_end

			if !(ty_is_array_or_slice(e.range.type) || ty_is_range(e.range.type) || ty_is_string(e.range.type)) {
				log_spanned_errorf(&e.range.span, "Internal Compiler Error: codegen got a for loop trying to iterate over an expression of type '{}', only arrays, slices, strings, and ranges are permitted.", e.range.type.name)
				return nil, false
			}

			range_v := cg_emit_expr(ctx, e.range) or_return
			if !epoch.ty_is_ptr(range_v.type) {
				log_spanned_error(&e.range.span, "Internal Compiler Error: for loop iterator is not a pointer to a struct. We do not support iterating over primitives")
				return nil, false
			}

			range_v_dbg_ty := cg_get_debug_type(mod, e.range.type, &e.range.span) or_return

			e.body.cg_val = dst_slot // inherit parent slot so it doesn't allocate its own

			loop_header := epoch.new_region(fn, "loop.header")
			last_start := ctx.cg_loop_start
			defer ctx.cg_loop_start = last_start
			ctx.cg_loop_start = loop_header

			iv_slot := epoch.add_local(fn, ty_builtin_rawptr.size, ty_builtin_rawptr.alignment)

			// Induction Variable Init
			{
				if ty_is_range(e.range.type) {
					// for i in [start..end)
					range, is_range := e.range.derived_expr.(^RangeExpr)
					assert(is_range, "THISISNOTARANGETHISISNOTARANGETHISISNOTARANGE")

					// TODO: These getmemberptrs can be moved to the header since they don't change
					start_mem_ptr := epoch.insr_getmemberptr(fn, range_v, range_v_dbg_ty, "start")

					// Maybe we should load these as a different type but ptr matches the register size so i think it's fine...
					start_v := epoch.insr_load(fn, epoch.TY_PTR, start_mem_ptr, false)
					if !range.left_bound_inclusive {
						one_const := epoch.new_int_const(fn, epoch.TY_PTR, u64(1))
						start_v = epoch.insr_add(fn, start_v, one_const)
					}

					epoch.insr_store(fn, iv_slot, start_v, false)
				} else if ty_is_string(e.range.type) || ty_is_array_or_slice(e.range.type) {
					// for v in wtv
					zero_const := epoch.new_int_const(fn, epoch.TY_PTR, u64(0))
					epoch.insr_store(fn, iv_slot, zero_const, false)
				} else {
					unreachable()
				}
			}

			loop_body := epoch.new_region(fn, "loop.body")

			epoch.insr_goto(fn, loop_header)
			epoch.set_control(fn, loop_header)

			// Loop predicate
			cond_v: ^epoch.Node
			{
				if ty_is_range(e.range.type) {
					// for i in [start..end)
					range, is_range := e.range.derived_expr.(^RangeExpr)
					assert(is_range, "THISISNOTARANGETHISISNOTARANGETHISISNOTARANGE")

					end_mem_ptr := epoch.insr_getmemberptr(fn, range_v, range_v_dbg_ty, "end")
					// If we load this each loop we tolerate the range changing during the loop. Is that reasonable?
					end_v := epoch.insr_load(fn, epoch.TY_PTR, end_mem_ptr, false)
					iv_v := epoch.insr_load(fn, epoch.TY_PTR, iv_slot, false)

					if range.right_bound_inclusive {
						cond_v = epoch.insr_cmp_sle(fn, iv_v, end_v)
					} else {
						cond_v = epoch.insr_cmp_slt(fn, iv_v, end_v)
					}
				} else if ty_is_string(e.range.type) || ty_is_slice(e.range.type) {
					// for v in slice_or_string
					count_mem_ptr := epoch.insr_getmemberptr(fn, range_v, range_v_dbg_ty, "end")
					count_v := epoch.insr_load(fn, epoch.TY_PTR, count_mem_ptr, false)
					iv_v := epoch.insr_load(fn, epoch.TY_PTR, iv_slot, false)

					cond_v = epoch.insr_cmp_ult(fn, iv_v, count_v)
				} else if ty_is_array(e.range.type) {
					// for v in arr
					log_spanned_error(&e.range.span, "impl range iter codegen")
					return nil, false
				} else {
					unreachable()
				}
			}

			epoch.insr_br(fn, cond_v, loop_body, loop_end)

			epoch.set_control(fn, loop_body)

			cg_emit_expr(ctx, e.body) or_return

			epoch.insr_goto(fn, loop_header)

			epoch.set_control(fn, loop_end)
			return dst_slot, true
		case ^WhileLoop:
			fn := ctx.cg_fn
			assert(fn != nil)

			dst_slot: ^epoch.Node
			if !ty_is_void(e.type) {
				dst_slot = epoch.add_local(fn, e.type.size, e.type.alignment)
				e.cg_val = dst_slot
			}

			loop_end := epoch.new_region(fn, "loop.end")
			last_end := ctx.cg_loop_end
			defer ctx.cg_loop_end = last_end
			ctx.cg_loop_end = loop_end

			loop_header := epoch.new_region(fn, "loop.header")
			last_start := ctx.cg_loop_start
			defer ctx.cg_loop_start = last_start
			ctx.cg_loop_start = loop_header

			epoch.insr_goto(fn, loop_header) // We have to reuse the condition check every loop so just jmp
			epoch.set_control(fn, loop_header)

			true_val := epoch.new_int_const(fn, epoch.TY_BOOL, i64(1))
			cond_v := cg_emit_expr(ctx, e.cond) or_return
			cmp := epoch.insr_cmp_eq(fn, cond_v, true_val)

			loop_body := epoch.new_region(fn, "loop.body")

			epoch.insr_br(fn, cmp, loop_body, loop_end)

			epoch.set_control(fn, loop_body)

			e.body.cg_val = dst_slot
			cg_emit_expr(ctx, e.body) or_return

			epoch.insr_goto(fn, loop_header) // go see if we should break out now

			epoch.set_control(fn, loop_end)

			return dst_slot, true
		case ^InfiniteLoop:
			fn := ctx.cg_fn
			assert(fn != nil)

			loop_end := epoch.new_region(fn, "loop.end")
			last_end := ctx.cg_loop_end
			defer ctx.cg_loop_end = last_end
			ctx.cg_loop_end = loop_end

			loop_body := epoch.new_region(fn, "loop.body")
			last_start := ctx.cg_loop_start
			defer ctx.cg_loop_start = last_start
			ctx.cg_loop_start = loop_body

			dst_slot: ^epoch.Node
			if !ty_is_void(e.type) {
				dst_slot = epoch.add_local(fn, e.type.size, e.type.alignment)
				e.cg_val = dst_slot
			}

			epoch.insr_goto(fn, loop_body)
			epoch.set_control(fn, loop_body)

			e.body.cg_val = dst_slot
			cg_emit_expr(ctx, e.body) or_return

			epoch.set_control(fn, loop_end)

			return dst_slot, true
		case ^RangeExpr:
			fn := ctx.cg_fn
			assert(fn != nil) // FIXME: globals (maybe make the global like a global function since it kinda is that)

			mod := ctx.checker.cg_module
			assert(mod != nil)

			lhs := cg_emit_expr(ctx, e.lhs) or_return
			rhs := cg_emit_expr(ctx, e.rhs) or_return

			dbg_ty := cg_get_debug_type(mod, e.type, &e.span) or_return
			lit_slot := epoch.add_local(fn, e.lhs.type.size, e.lhs.type.alignment)

			start_ptr := epoch.insr_getmemberptr(fn, lit_slot, dbg_ty, "start")
			epoch.insr_store(fn, start_ptr, lhs, false)

			end_ptr := epoch.insr_getmemberptr(fn, lit_slot, dbg_ty, "end")
			epoch.insr_store(fn, end_ptr, rhs, false)

			return lit_slot, true
		case ^UnaryOpExpr:
		case ^BinOpExpr: return cg_emit_binop(ctx, e)
		case ^ProcCallExpr:
		case ^PrimitiveTypeExpr:
			log_spanned_errorf(&e.span, "Internal Compiler Error: Got unexpected primitive type expression in cg_emit_expr")
			return nil, false
		case ^PointerTypeExpr:
			log_spanned_errorf(&e.span, "Internal Compiler Error: Got unexpected pointer type expression in cg_emit_expr")
			return nil, false
		case ^SliceTypeExpr:
			log_spanned_errorf(&e.span, "Internal Compiler Error: Got unexpected slice type expression in cg_emit_expr")
			return nil, false
		case ^ArrayTypeExpr:
			log_spanned_errorf(&e.span, "Internal Compiler Error: Got unexpected array type expression in cg_emit_expr")
			return nil, false
	}

	log_spanned_error(&expr.span, "impl cg_emit_expr")
	return nil, false
}

cg_emit_binop :: proc(ctx: ^CheckerContext, binop: ^BinOpExpr) -> (^epoch.Node, bool) {
	l_ty := binop.lhs.type
	r_ty := binop.rhs.type

	if !ty_eq(l_ty, r_ty) {
		log_spanned_errorf(&binop.span, "Internal Compiler Error: codegen received a binop with two different types '{}' and '{}'", l_ty.name, r_ty.name)
		return nil, false
	}

	if ty_is_number(l_ty) {
		return cg_emit_binop_number(ctx, binop)
	} else if ty_is_array(l_ty) {
		return cg_emit_binop_array(ctx, binop)
	}

	log_spanned_errorf(&binop.op.span, "Internal Compiler Error: codegen received a binary op of invalid type '{}'", l_ty.name)
	return nil, false
}

cg_emit_binop_array :: proc(ctx: ^CheckerContext, binop: ^BinOpExpr) -> (^epoch.Node, bool) {
	assert(ty_is_array(binop.type))
	// Only the basics are supported for arrays
	#partial switch binop.op.kind {
		case .Star:
		case .Slash:
		case .Plus:
		case .Minus:
	}

	log_spanned_error(&binop.op.span, "Internal Compiler Error: codegen got an invalid binary expression on arrays")
	return nil, false
}

cg_load_number_val :: proc(ctx: ^CheckerContext, expr: ^Expr) -> (n: ^epoch.Node, ok: bool) {
	fn := ctx.cg_fn
	rand := expr.cg_val

	assert(epoch.ty_is_ptr(rand.type))

	debug_type := cg_get_debug_type(ctx.checker.cg_module, expr.type, &expr.span) or_return
	dbg_ty_reg := epoch.get_debug_type_register_class(debug_type)
	reg_ty := epoch.get_type_with_register_class(dbg_ty_reg, debug_type)

	// TODO(RD): Hook this up with the type system (probably not a problem for this
	//           but will be for explicit deref)
	is_volatile := false

	return epoch.insr_load(fn, reg_ty, expr.cg_val, is_volatile), true
}

cg_emit_binop_number :: proc(ctx: ^CheckerContext, binop: ^BinOpExpr) -> (res: ^epoch.Node, ok: bool) {
	assert(ty_eq(binop.lhs.type, binop.rhs.type))
	assert(ty_is_number(binop.lhs.type))

	lhs := cg_emit_expr(ctx, binop.lhs) or_return
	rhs := cg_emit_expr(ctx, binop.rhs) or_return

	// We need to load the lhs value if its not the dst for a store (ie any non-assigning op)
	if !is_mutating_op(binop.op.kind) && epoch.ty_is_ptr(lhs.type) {
		lhs = cg_load_number_val(ctx, binop.lhs) or_return
	}

	// Always load the value for the rhs since its going to be copied over
	if epoch.ty_is_ptr(rhs.type) {
		rhs = cg_load_number_val(ctx, binop.rhs) or_return
	}

	is_float := epoch.ty_is_float(lhs.type)
	is_signed_int := ty_is_signed_integer(binop.lhs.type)

	fn := ctx.cg_fn
	assert(fn != nil)

	#partial switch binop.op.kind {
		case .Star:
			if is_float {
				binop.cg_val = epoch.insr_fmul(fn, lhs, rhs)
			} else {
				binop.cg_val = epoch.insr_mul(fn, lhs, rhs)
			}
		case .Slash:
			if is_float {
				binop.cg_val = epoch.insr_fdiv(fn, lhs, rhs)
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_sdiv(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_udiv(fn, lhs, rhs)
				}
			}
		case .Percent:
			if is_float {
				log_spanned_error(&binop.op.span, "Internal Compiler Error: fmod instruction emission is not implemented :'(")
				return nil, false
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_smod(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_umod(fn, lhs, rhs)
				}
			}
		case .Plus:
			if is_float {
				binop.cg_val = epoch.insr_fadd(fn, lhs, rhs)
			} else {
				binop.cg_val = epoch.insr_add(fn, lhs, rhs)
			}
		case .Minus:
			if is_float {
				binop.cg_val = epoch.insr_fsub(fn, lhs, rhs)
			} else {
				binop.cg_val = epoch.insr_sub(fn, lhs, rhs)
			}
		case .LShift:
			assert(!is_float)
			binop.cg_val = epoch.insr_shl(fn, lhs, rhs)
		case .RShift:
			assert(!is_float)
			binop.cg_val = epoch.insr_shr(fn, lhs, rhs)
		case .LessThanOrEqual:
			if is_float {
				binop.cg_val = epoch.insr_cmp_fle(fn, lhs, rhs)
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_cmp_sle(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_cmp_ule(fn, lhs, rhs)
				}
			}
		case .LAngle:
			if is_float {
				binop.cg_val = epoch.insr_cmp_flt(fn, lhs, rhs)
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_cmp_slt(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_cmp_ult(fn, lhs, rhs)
				}
			}
		case .GreaterThanOrEqual:
			if is_float {
				binop.cg_val = epoch.insr_cmp_fge(fn, lhs, rhs)
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_cmp_sge(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_cmp_uge(fn, lhs, rhs)
				}
			}
		case .RAngle:
			if is_float {
				binop.cg_val = epoch.insr_cmp_fgt(fn, lhs, rhs)
			} else {
				if is_signed_int {
					binop.cg_val = epoch.insr_cmp_sgt(fn, lhs, rhs)
				} else {
					binop.cg_val = epoch.insr_cmp_ugt(fn, lhs, rhs)
				}
			}
		case .Equal:
			binop.cg_val = epoch.insr_cmp_eq(fn, lhs, rhs)
		case .NotEqual:
			binop.cg_val = epoch.insr_cmp_ne(fn, lhs, rhs)
		case .Ampersand, .DoubleAmpersand:
			// RD: Fix these to short-circuit
			assert(!is_float)
			binop.cg_val = epoch.insr_and(fn, lhs, rhs)
		case .Pipe, .DoublePipe:
			assert(!is_float)
			binop.cg_val = epoch.insr_or(fn, lhs, rhs)
		case .Caret, .DoubleCaret:
			assert(!is_float)
			binop.cg_val = epoch.insr_xor(fn, lhs, rhs)
		case .Assign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))
			// TODO(RD): Volatile bullshit for embedded cringelords (me)
			is_volatile := false
			epoch.insr_store(fn, lhs, rhs, is_volatile)
			binop.cg_val = nil
		case .PlusAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Plus
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .PlusAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .MinusAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Minus
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .MinusAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .StarAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Star
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .StarAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .SlashAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Slash
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .SlashAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .PercentAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Percent
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .PercentAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .AmpersandAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Ampersand
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .AmpersandAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .PipeAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Pipe
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .PipeAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case .CaretAssign:
			assert(epoch.ty_is_ptr(lhs.type))
			assert(!epoch.ty_is_ptr(rhs.type))

			// suck my balls this shit's funny
			binop.op.kind = .Caret
			sum_v := cg_emit_binop_number(ctx, binop) or_return
			binop.op.kind = .CaretAssign // None the wiser :D

			// TODO(RD): Volatile fuck shit
			is_volatile := false
			epoch.insr_store(fn, lhs, sum_v, is_volatile)
			binop.cg_val = nil
		case:
			log_spanned_error(&binop.op.span, "Internal Compiler Error: codegen for binary op is unimplemented")
			return nil, false
	}

	return binop.cg_val, true
}

