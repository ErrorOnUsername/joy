package main

import "core:math/big"
import "core:sync"
import "core:strings"
import "core:fmt"

import "../epoch"


tc_cycle_check_rec :: proc( pkg: ^Package, cycle_checker: ^[dynamic]^Package ) -> ( found_cycle := false, cycle_report := "<none>" )
{
	for parent_pkg in cycle_checker^ {
		if parent_pkg == pkg {
			found_cycle = true

			sb: strings.Builder
			defer strings.builder_destroy( &sb )

			fmt.sbprint( &sb, "[ " )
			for i := 0; i < len( cycle_checker ); i += 1 {
				p := cycle_checker[i]

				if i < len( cycle_checker ) - 1 {
					fmt.sbprintf( &sb, "{} -> ", pkg.name )
				} else {
					fmt.sbprintf( &sb, "{}", pkg.name )
				}
			}
			fmt.sbprint( &sb, " ]" )

			cycle_report = strings.clone( strings.to_string( sb ) )
			return
		}
	}

	append( cycle_checker, pkg )

	for p in pkg.imports {
		p_found_cycle, rep := tc_cycle_check_rec( p, cycle_checker )
		if p_found_cycle do return p_found_cycle, rep
	}

	pop( cycle_checker )

	return
}


tc_does_import_graph_contiain_cycles :: proc( root_pkg: ^Package ) -> ( found_cycle: bool, cycle_report: string )
{
	cycle_checker := make( [dynamic]^Package )
	defer delete( cycle_checker )

	found_cycle, cycle_report = tc_cycle_check_rec( root_pkg, &cycle_checker )
	if found_cycle do return found_cycle, cycle_report

	return
}


tc_build_graph_dag_topo :: proc( prio: ^int, list: ^[dynamic]PriorityItem( ^Package ), pkg: ^Package )
{
	for parent in pkg.imports {
		if prio^ != 0 {
			prio^ -= 1
		}

		tc_build_graph_dag_topo( prio, list, parent )
	}

	append( list, PriorityItem( ^Package ) { prio^, pkg } )

	prio^ += 1
}


tc_build_package_list :: proc( root_pkg: ^Package ) -> ( []PriorityItem( ^Package ), bool )
{
	contains_cycles, first_cycle := tc_does_import_graph_contiain_cycles( root_pkg )
	if contains_cycles {
		log_errorf( "Package import graph contains cycles: {}", first_cycle )
		return nil, false
	}

	prio := 0
	list := make( [dynamic]PriorityItem( ^Package ) )
	tc_build_graph_dag_topo( &prio, &list, root_pkg )

	return list[:], true
}


ProcBodyWorkData :: struct
{
	p: ^ProcProto,
	m: ^Module,
}

Checker :: struct
{
	proc_work_mutex: sync.Mutex,
	proc_bodies:     [dynamic]ProcBodyWorkData,
	cg_module:       ^epoch.Module,
}


tc_initialize_scopes :: proc( c: ^Checker, pkgs: []PriorityItem( ^Package ) ) -> int
{
	for pkg in pkgs {
		for mod in pkg.item.modules {
			compiler_enqueue_work( .InitializeScopes, file_id = mod.file_id, checker = c )
		}
	}

	failed_tasks := compiler_finish_work()
	return failed_tasks
}


pump_tc_init_scopes :: proc( file_id: FileID, c: ^Checker ) -> PumpResult
{
	fd := fm_get_data( file_id )

	sc := fd.mod.file_scope
	ok := tc_initialize_in_scope( c, sc )

	return .Continue if ok else .Error
}


tc_initialize_in_scope :: proc( c: ^Checker, s: ^Scope ) -> bool
{
	s.symbols = make( SymbolTable )

	for stmnt in s.stmnts {
		switch st in stmnt.derived_stmnt {
			case ^ConstDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of symbol '{:s}'", st.name )
					return false
				}

				#partial switch v in st.value.derived_expr {
					case ^Scope:
						scope_ok := tc_initialize_in_scope( c, v )
						if !scope_ok do return false
					case ^ProcProto:
						scope_ok := tc_initialize_in_scope( c, v.body )
						if !scope_ok do return false
				}

				s.symbols[st.name] = stmnt
			case ^VarDecl: // These don't need to be added yet. We just need to know about top-level decl names.

			case ^EnumVariantDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of enum variant '{:s}'", st.name )
					return false
				}

				s.symbols[st.name] = stmnt
			case ^UnionVariantDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of union variant '{:s}'", st.name )
					return false
				}

				s.symbols[st.name] = stmnt
			case ^ExprStmnt: // These aren't bound to symbols
			case ^ContinueStmnt:
			case ^BreakStmnt:
			case ^ReturnStmnt:
		}
	}

	return true
}


tc_check_package_dag :: proc( c: ^Checker, pkgs: []PriorityItem(^Package) ) -> int
{
	tasks_failed := 0
	curr_prio := 0

	for pkg in pkgs {
		if pkg.priority != curr_prio {
			tasks_failed = compiler_finish_work()
		}
		if tasks_failed != 0 do break

		compiler_enqueue_work( .CheckPackage, pkg = pkg.item, checker = c )
	}
	tasks_failed = compiler_finish_work()

	return tasks_failed
}


tc_check_proc_bodies :: proc( c: ^Checker ) -> int
{
	for p in c.proc_bodies {
		compiler_enqueue_work( .CheckProcBody, checker = c, proc_proto = p.p, module = p.m )
	}

	return compiler_finish_work()
}


pump_tc_check_proc_body :: proc( c: ^Checker, p: ^ProcProto, m: ^Module ) -> PumpResult
{
	ctx: CheckerContext
	ctx.curr_scope = p.body
	ctx.curr_proc = p
	ctx.checker = c
	ctx.mod = m
	fn_node := p.cg_val
	assert(fn_node.kind == .Symbol)
	sym, is_sym := fn_node.extra.(^epoch.SymbolExtra)
	assert(is_sym)
	ctx.cg_fn = sym.sym.derived.(^epoch.Function)

	for stmnt in p.body.stmnts {
		stmnt_ok := tc_check_stmnt( &ctx, stmnt )
		if !stmnt_ok do return .Error
	}

	return .Continue
}


pump_tc_check_pkg :: proc( c: ^Checker, pkg: ^Package ) -> PumpResult
{
	// Single-threadedly check top level declarations of the
	// package and queue up procedure bodies to be checked
	// in parallel

	for m in pkg.modules {
		ctx: CheckerContext
		ctx.checker = c
		ctx.mod = m
		ctx.curr_scope = m.file_scope

		for stmnt in m.file_scope.stmnts {
			stmnt_ok := tc_check_stmnt( &ctx, stmnt )
			if !stmnt_ok do return .Error
		}
	}

	return .Continue
}


tc_check_stmnt :: proc( ctx: ^CheckerContext, stmnt: ^Stmnt ) -> bool
{
	switch s in stmnt.derived_stmnt {
		case ^ConstDecl:
			if s.type_hint != nil {
				ty := tc_check_type( ctx, s.type_hint )
				if ty == nil do return false

				s.type = ty
			}

			last_hint_ty := ctx.hint_type
			ctx.hint_type = s.type
			defer ctx.hint_type = last_hint_ty

			if s.value != nil {
				ty, addr_mode := tc_check_expr( ctx, s.value )
				if ty == nil do return false

				if addr_mode == .Invalid {
					log_spanned_error( &s.value.span, "Expression does produce a value" )
					return false
				}

				if s.type_hint != nil && !ty_eq(s.type, ty) {
					if !ty_is_untyped_builtin( ty ) {
						log_spanned_errorf( &s.value.span, "Value of type '{}' cannot be assigned to identifier of type '{}'", ty.name, s.type.name )
						return false
					}

					ellide_ok := try_ellide_untyped_to_ty( s.value, s.type )
					if !ellide_ok {
						log_spanned_error( &s.span, "Could not ellide untyped expression to specified type of constant" )
						return false
					}
				} else if ty_is_untyped_builtin( ty ) {
					ty = get_untyped_default_concrete_ty( ty )
					s.value.type = ty
				}

				s.type = ty
			}

			// This should've been a syntax error, but just in case...
			assert( s.type_hint != nil || s.value != nil )
		case ^VarDecl:
			if s.name in ctx.curr_scope.symbols {
				log_spanned_errorf( &s.span, "Redefinition of variable '{:s}'", s.name )
				return false
			}

			if s.type_hint != nil {
				ty := tc_check_type( ctx, s.type_hint )
				if ty == nil do return false

				s.type = ty
			}

			last_hint_ty := ctx.hint_type
			ctx.hint_type = s.type
			defer ctx.hint_type = last_hint_ty

			if s.default_value != nil {
				ty, addr_mode := tc_check_expr( ctx, s.default_value )
				if ty == nil do return false

				if addr_mode == .Invalid {
					log_spanned_error( &s.default_value.span, "Expression does not produce a value" )
					return false
				}

				if s.type != nil && !ty_eq(s.type, ty) {
					if !ty_is_untyped_builtin( ty ) {
						log_spanned_errorf( &s.default_value.span, "Value of type '{}' cannot be assigned to identifier of type '{}'", ty.name, s.type.name )
						return false
					}

					ellide_ok := try_ellide_untyped_to_ty( s.default_value, s.type )
					if !ellide_ok {
						log_spanned_error( &s.span, "Could not ellide untyped expression to specified type of constant" )
						return false
					}
				} else if ty_is_untyped_builtin( ty ) {
					ty = get_untyped_default_concrete_ty( ty )
					s.default_value.type = ty
					s.type = ty
				}
			}

			assert( s.type_hint != nil || s.default_value != nil, "Internal Compiler Error: VarDecl must have at least a type hint or a default value" )

			ctx.curr_scope.symbols[s.name] = s
		case ^EnumVariantDecl:
			sc := ctx.curr_scope
			assert( sc.variant == .Enum, "Enum variant declared outside of enum scope" )
			assert( ty_is_enum( ctx.hint_type ) )

			s.type = ctx.hint_type
		case ^UnionVariantDecl:
			variant_type := new_type( StructType, ctx.mod, s.name )
			variant_type.ast_scope = s.sc

			last_scope := ctx.curr_scope
			defer ctx.curr_scope = last_scope
			ctx.curr_scope = s.sc

			size := 0
			align := 0
			for stmnt in s.sc.stmnts {
				mem_ok := tc_check_stmnt( ctx, stmnt )
				if !mem_ok do return false

				v, v_ok := stmnt.derived_stmnt.(^VarDecl)
				if !v_ok {
					log_spanned_error( &stmnt.span, "Expected enum variant member to be a variable declaration" )
					return false
				}

				align = max( align, stmnt.type.alignment )

				st_mem := StructMember { v.name, stmnt.type, size }
				if (size + stmnt.type.size) / align == 0 {
					size += stmnt.type.size
				} else {
					size += (align - size) + stmnt.type.size
				}

				append( &variant_type.members, st_mem )
			}

			variant_type.size = size
			variant_type.alignment = align

			s.type = variant_type
		case ^ExprStmnt:
			ty, addr_mode := tc_check_expr( ctx, s.expr )
			if ty == nil do return false

			if addr_mode == .Invalid {
				log_spanned_error( &s.expr.span, "Expression does not produce a value" )
				return false
			}

			if !ty_is_void( ty ) {
				log_spanned_error( &s.span, "Expression produces a value, but that value is discarded. If this is intentional, consider assigning it to the discard identifier: '_'" )
				return false
			}
		case ^ContinueStmnt:
			if ctx.curr_loop == nil {
				log_spanned_error( &s.span, "'continue' statements are only prermitted within loops" )
				return false
			}
		case ^BreakStmnt:
			if ctx.curr_loop == nil {
				log_spanned_error( &s.span, "'break' statements are only prermitted within loops" )
				return false
			}
		case ^ReturnStmnt:
			if ctx.curr_proc == nil {
				log_spanned_error( &s.span, "'return' statements are only permitted within funcitons" )
				return false
			}

			ty, addr_mode := tc_check_expr( ctx, s.expr )
			if ty == nil do return false

			if addr_mode == .Invalid {
				log_spanned_error( &s.expr.span, "Expression does not produce a value" )
				return false
			}

			proc_ty := ctx.curr_proc.type.derived.(^FnType)

			if !ty_eq(ty, proc_ty.return_type) {
				log_spanned_errorf( &s.span, "return expression's type does not match the return type of the function. Expected '{}' got '{}'", proc_ty.return_type.name, ty.name )
				return false
			}
	}

	stmnt.check_state = .Resolved

	// only run codegen for statments at top-level or in a logic scope
	if ctx.curr_scope.variant == .File || ctx.curr_scope.variant == .Logic {
		cg_emit_stmnt( ctx, stmnt ) or_return
	}

	return true
}


try_ellide_untyped_to_ty :: proc( untyped_expr: ^Expr, to_ty: ^Type ) -> bool
{
	assert( ty_is_untyped_builtin( untyped_expr.type ) )

	u_ty := untyped_expr.type

	if u_ty == ty_builtin_untyped_string {
		if !ty_is_prim( to_ty, .String ) && !ty_is_prim( to_ty, .CString ) {
			return false
		}
	} else if u_ty == ty_builtin_untyped_int {
		if !ty_is_number( to_ty ) {
			return false
		}
	} else {
		unreachable()
	}

	untyped_expr.type = to_ty

	return true
}


get_untyped_default_concrete_ty :: proc( untyped_ty: ^Type ) -> ^Type
{
	assert( ty_is_untyped_builtin( untyped_ty ) )

	if untyped_ty == ty_builtin_untyped_int {
		return ty_builtin_isize
	} else if untyped_ty == ty_builtin_untyped_string {
		return ty_builtin_string
	}

	return nil
}


tc_check_type :: proc( ctx: ^CheckerContext, type_expr: ^Expr ) -> ^Type
{
	ty, addr_mode := tc_check_expr( ctx, type_expr )
	if ty == nil do return nil

	if addr_mode == .Invalid {
		log_spanned_error( &type_expr.span, "invalid expression" )
		return nil
	}

	if !ty_is_prim(ty, .TypeID) {
		log_spanned_error( &type_expr.span, "expression is not type" )
		return nil
	}

	return type_expr.to_ty
}


tc_check_expr :: proc( ctx: ^CheckerContext, expr: ^Expr ) -> (^Type, AddressingMode)
{
	switch ex in expr.derived_expr {
		case ^ProcProto:
			last_scope := ctx.curr_scope
			ctx.curr_scope = ex.body
			defer ctx.curr_scope = last_scope

			ty := new_type( FnType, ctx.mod, "fn" )

			for p in ex.params {
				if p.name in ex.body.symbols {
					log_spanned_error( &p.span, "Redefinition of function parameter" )
					return nil, .Invalid
				}

				if p.type_hint != nil {
					hint_ty := tc_check_type( ctx, p.type_hint )
					if hint_ty == nil do return nil, .Invalid

					p.type = hint_ty
				}

				last_hint_ty := ctx.hint_type
				ctx.hint_type = p.type
				defer ctx.hint_type = last_hint_ty

				if p.default_value != nil {
					v_ty, addr_mode := tc_check_expr( ctx, p.default_value )
					if v_ty == nil do return nil, .Invalid

					if addr_mode == .Invalid {
						log_spanned_error( &p.default_value.span, "Expression does not produce a value" )
						return nil, .Invalid
					}

					if p.type != nil && !ty_eq(p.type, v_ty) {
						if !ty_is_untyped_builtin( v_ty ) {
							log_spanned_errorf( &p.default_value.span, "Value of type '{}' cannot be assigned to parameter of type '{}'", v_ty.name, p.type.name )
							return nil, .Invalid
						}

						ellide_ok := try_ellide_untyped_to_ty( p.default_value, p.type )
						if !ellide_ok {
							log_spanned_errorf( &p.span, "Could not ellide '{}' to '{}'", p.default_value.type.name, p.type.name )
							return nil, .Invalid
						}
					} else if ty_is_untyped_builtin( v_ty ) {
						v_ty = get_untyped_default_concrete_ty( v_ty )
						p.default_value.type = v_ty
					}

					p.type = v_ty
				}

				p.check_state = .Resolved
				append( &ty.params, p.type )

				ex.body.symbols[p.name] = p
			}

			if ex.return_type != nil {
				return_ty := tc_check_type( ctx, ex.return_type )
				if return_ty == nil do return nil, .Invalid

				ty.return_type = return_ty
			} else {
				ty.return_type = ty_builtin_void
			}

			ex.type = ty

			assert(ex.body != nil)

			sync.mutex_lock( &ctx.checker.proc_work_mutex )
			defer sync.mutex_unlock( &ctx.checker.proc_work_mutex )

			data := ProcBodyWorkData { ex, ctx.mod }
			append( &ctx.checker.proc_bodies, data )

			return ty, .RValue
		case ^Ident:
			def := lookup_ident( ctx, ex.name )
			if def == nil {
				log_spanned_errorf( &ex.span, "Undeclared identifier '{}'", ex.name )
				return nil, .Invalid
			}

			if def.check_state != .Resolved {
				def_ok := tc_check_stmnt( ctx, def )
				if !def_ok do return nil, .Invalid
			}

			ty: ^Type
			switch st in def.derived_stmnt {
				case ^ConstDecl:
					val := st.value
					#partial switch v in val.derived_expr {
						case ^Scope:
							assert( v.variant != .Logic, "Logic scope assigned to constant" )
							assert( st.type != nil, "Statement doesn't have type" )
							ex.to_ty = st.type
							ty = ty_builtin_typeid
						case:
							ty = st.type
					}

				case ^EnumVariantDecl:
					ty = st.type
				case ^UnionVariantDecl:
					ty = st.type
				case ^VarDecl:
					ty = st.type

				case ^ExprStmnt:
				case ^ContinueStmnt:
				case ^BreakStmnt:
				case ^ReturnStmnt:
					panic( "Internal Compiler Error: Identifer references bindless statement" )
			}

			ex.type = ty

			return ty, .LValue
		case ^StringLiteralExpr:
			ex.type = ty_builtin_untyped_string
			if !get_string_literal_value(ctx, ex) do return nil, .Invalid

			return ex.type, .RValue
		case ^NumberLiteralExpr:
			if !get_number_literal_value(ctx, ex) do return nil, .Invalid

			switch v in ex.val {
				case big.Int: ex.type = ty_builtin_untyped_int
				case f64:     ex.type = ty_builtin_untyped_float
			}

			return ex.type, .RValue
		case ^NamedStructLiteralExpr:
			decl := lookup_ident( ctx, ex.name )
			if decl == nil {
				log_spanned_errorf( &ex.span, "undeclared struct or union variant '{}'", ex.name )
				return nil, .Invalid
			}

			last_ctx_ty := ctx.hint_type
			defer ctx.hint_type = last_ctx_ty
			ctx.hint_type = nil

			if !ty_is_struct( decl.type ) {
				log_spanned_errorf( &ex.span, "'{}' does not reference a struct or enum variant", ex.name )
				return nil, .Invalid
			}

			struct_ty := decl.type.derived.(^StructType)

			if len( ex.vals ) != len( struct_ty.members ) {
				log_spanned_errorf( &ex.span, "struct '{}' has {} members, but you supplied {} values", ex.name, len( struct_ty.members ), len( ex.vals ) )
				return nil, .Invalid
			}

			for i in 0..<len( ex.vals ) {
				val_ty, val_addr_mode := tc_check_expr( ctx, ex.vals[i] )
				if val_ty == nil do return nil, .Invalid

				if val_addr_mode == .Invalid {
					log_spanned_error( &ex.vals[i].span, "expected value" )
					return nil, .Invalid
				}

				if ty_is_untyped_builtin( val_ty ) {
					ok := try_ellide_untyped_to_ty( ex.vals[i], struct_ty.members[i].ty )
					if !ok {
						log_spanned_errorf( &ex.vals[i].span, "could not implicity cast '{}' to '{}'", ex.vals[i].type.name, struct_ty.members[i].ty.name )
						return nil, .Invalid
					}

					val_ty = ex.vals[i].type
				}

				if !ty_eq(val_ty, struct_ty.members[i].ty) {
					log_spanned_errorf( &ex.vals[i].span, "expected '{}' got '{}'", struct_ty.members[i].ty.name, val_ty.name )
					return nil, .Invalid
				}
			}

			ex.type = struct_ty if !ty_is_union( last_ctx_ty ) else last_ctx_ty

			return ex.type, .RValue
		case ^AnonStructLiteralExpr:
			if ctx.hint_type == nil {
				log_spanned_error( &ex.span, "Cannot infer structure literal type without hint" )
				return nil, .Invalid
			}

			if !ty_is_struct( ctx.hint_type ) {
				log_spanned_errorf( &ex.span, "'{}' is not a struct or enum variant", ctx.hint_type.name )
				return nil, .Invalid
			}

			struct_ty := ctx.hint_type.derived.(^StructType)

			if len( ex.vals ) != len( struct_ty.members ) {
				log_spanned_errorf( &ex.span, "struct '{}' has {} members, but you supplied {} values", struct_ty.name, len( ex.vals ), len( struct_ty.members ) )
				return nil, .Invalid
			}

			for i in 0..<len( ex.vals ) {
				val_ty, val_addr_mode := tc_check_expr( ctx, ex.vals[i] )
				if val_ty == nil do return nil, .Invalid

				if val_addr_mode == .Invalid {
					log_spanned_error( &ex.vals[i].span, "expected value" )
					return nil, .Invalid
				}

				if ty_is_untyped_builtin( val_ty ) {
					ok := try_ellide_untyped_to_ty( ex.vals[i], struct_ty.members[i].ty )
					if !ok {
						log_spanned_errorf( &ex.vals[i].span, "could not implicity cast '{}' to '{}'", val_ty.name, struct_ty.members[i].ty.name )
						return nil, .Invalid
					}

					val_ty = ex.vals[i].type
				}

				if !ty_eq(val_ty, struct_ty.members[i].ty) {
					log_spanned_errorf( &ex.vals[i].span, "expected '{}' got '{}'", struct_ty.members[i].ty.name, val_ty.name )
					return nil, .Invalid
				}
			}

			ex.type = struct_ty

			return struct_ty, .RValue
		case ^MemberAccessExpr:
			owner_ty, owner_addr_mode := tc_check_expr( ctx, ex.val )
			if owner_ty == nil do return nil, .Invalid

			if owner_addr_mode == .Invalid {
				log_spanned_error( &ex.val.span, "Expression does not produce a value" )
				return nil, .Invalid
			}

			base_ty := ty_get_base(owner_ty)

			last_ctx_ty := ctx.hint_type
			defer ctx.hint_type = last_ctx_ty

			member_access_get_field_name :: proc(m: ^Expr) -> (string, ^Expr) {
				assert(m != nil)
				#partial switch f in m.derived_expr {
					case ^Ident:
						return f.name, f
					case ^ProcCallExpr:
						return f.name, f
					case ^NamedStructLiteralExpr:
						return f.name, f
					case ^MemberAccessExpr:
						return member_access_get_field_name( f.val )
				}
				return "", nil
			}

			cur_ty := owner_ty
			addr_mode: AddressingMode
			field := ex.member
			for field != nil {
				member_name, member_expr := member_access_get_field_name(field)
				member_ty := ty_get_member(cur_ty, member_name)
				if member_ty == nil {
					log_spanned_errorf( &field.span, "field '{}' is not a member of type '{}'", member_name, cur_ty.name )
					return nil, .Invalid
				}

				ctx.hint_type = cur_ty
				c_mem_ty: ^Type
				c_mem_ty, addr_mode = tc_check_expr( ctx, member_expr )
				assert(ty_eq(c_mem_ty, member_ty))

				chain_mem_access, is_mem_access := field.derived_expr.(^MemberAccessExpr)
				field = chain_mem_access.member if is_mem_access else nil
				cur_ty = c_mem_ty
			}

			ex.type = cur_ty

			return ex.type, addr_mode
		case ^ImplicitSelectorExpr:
			ctx_ty := ctx.hint_type
			if ctx_ty == nil {
				log_spanned_error( &ex.span, "ambiguous use of implicit selector" )
				return nil, .Invalid
			}

			return tc_check_expr( ctx, ex.member )
		case ^Scope:
			last_scope := ctx.curr_scope
			ctx.curr_scope = ex
			defer ctx.curr_scope = last_scope;

			switch ex.variant {
				case .File:
					unreachable()
				case .Struct:
					struct_type := new_type( StructType, ctx.mod, "struct" )
					struct_type.ast_scope = ex

					size := 0
					align := 0
					for m in ex.stmnts {
						v, v_ok := m.derived_stmnt.(^VarDecl)
						if !v_ok {
							log_spanned_error( &m.span, "Expected struct member to be a variable declaration" )
							return nil, .Invalid
						}

						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid

						align = max( align, m.type.alignment )

						st_mem := StructMember { v.name, m.type, size }

						if (size + m.type.size) / align == 0 {
							size += m.type.size
						} else {
							size += (align - size) + m.type.size
						}

						append( &struct_type.members, st_mem )
					}

					struct_type.size = size
					struct_type.alignment = align

					ex.type = struct_type
					return struct_type, .RValue
				case .Union:
					union_type := new_type( UnionType, ctx.mod, "union" )
					union_type.ast_scope = ex
					union_type.size = 0
					union_type.alignment = 0

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid

						struct_ty, is_struct := m.type.derived.(^StructType)
						if !is_struct {
							log_spanned_error( &m.span, "Union variant must be a struct type" )
							return nil, .Invalid
						}

						union_type.size = max( union_type.size, struct_ty.size )
						union_type.size = max( union_type.alignment, struct_ty.alignment )

						append( &union_type.variants, struct_ty )
					}

					ex.type = union_type
					return union_type, .RValue
				case .Enum:
					enum_type := new_type( EnumType, ctx.mod, "enum" )
					enum_type.ast_scope = ex
					enum_type.underlying = ty_builtin_usize
					enum_type.size = enum_type.underlying.size
					enum_type.alignment = enum_type.underlying.alignment

					last_ctx_ty := ctx.hint_type
					ctx.hint_type = enum_type
					defer ctx.hint_type = last_ctx_ty

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid
					}

					ex.type = enum_type
					return enum_type, .RValue
				case .Logic:
					ex.type = ty_builtin_void

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid
					}

					return ex.type, .RValue
			}
		case ^IfExpr:
			if ex.cond != nil {
				cond_ty, addr_mode := tc_check_expr( ctx, ex.cond )
				if cond_ty == nil do return nil, .Invalid

				if addr_mode == .Invalid {
					log_spanned_error( &ex.cond.span, "expected value" )
					return nil, .Invalid
				}

				if !ty_is_bool(cond_ty)  {
					log_spanned_errorf( &ex.cond.span, "expected 'bool' got '{}'", cond_ty.name )
					return nil, .Invalid
				}
			}

			then_ty, addr_mode := tc_check_expr( ctx, ex.then )
			if then_ty == nil do return nil, .Invalid

			yeild_ty := then_ty

			if ex.else_block != nil {
				else_ty, addr_mode := tc_check_expr( ctx, ex.else_block )
				if else_ty == nil do return nil, .Invalid

				if !ty_eq(then_ty, else_ty) {
					log_spanned_error( &ex.else_block.span, "not all branches yeild the same type" )
					return nil, .Invalid
				}
			}

			ex.type = yeild_ty

			return yeild_ty, .RValue
		case ^ForLoop:
			range_ty, addr_mode := tc_check_expr( ctx, ex.range )
			if range_ty == nil do return nil, .Invalid

			if addr_mode == .Invalid {
				log_spanned_error( &ex.range.span, "for loop range expression does not reference a value" )
				return nil, .Invalid
			}

			if ty_is_range( range_ty ) {
				ex.iter.type = ty_builtin_isize
			} else if ty_is_array_or_slice( range_ty ) {
				ex.iter.type = ty_get_array_underlying( range_ty )
			} else {
				log_spanned_error( &ex.range.span, "for loop iterator expression is not an array, slice, or range" )
				return nil, .Invalid
			}

			assert( !(ex.iter.name in ex.body.symbols) )

			ex.body.symbols[ex.iter.name] = ex.iter

			ctx.curr_loop = ex

			body_ty, body_addr_mode := tc_check_expr( ctx, ex.body )
			if body_ty == nil do return nil, .Invalid

			if body_addr_mode == .Invalid {
				log_spanned_error( &ex.body.span, "expected value" )
				return nil, .Invalid
			}

			ex.type = body_ty

			return body_ty, .RValue
		case ^WhileLoop:
			cond_ty, addr_mode := tc_check_expr( ctx, ex.cond )
			if cond_ty == nil do return nil, .Invalid

			if addr_mode == .Invalid {
				log_spanned_error( &ex.cond.span, "while loop condition does not represent a value" )
				return nil, .Invalid
			}

			if !ty_is_bool( cond_ty ) {
				log_spanned_errorf( &ex.cond.span, "expected 'bool' got '{}'", cond_ty.name )
				return nil, .Invalid
			}

			ctx.curr_loop = ex

			body_ty, _ := tc_check_expr( ctx, ex.body )
			if body_ty == nil do return nil, .Invalid

			ex.type = body_ty

			return body_ty, .RValue
		case ^InfiniteLoop:
			ctx.curr_loop = ex

			body_ty, _ := tc_check_expr( ctx, ex.body )
			if body_ty == nil do return nil, .Invalid

			ex.type = body_ty

			return body_ty, .RValue
		case ^RangeExpr:
			start_ty, s_addr_mode := tc_check_expr( ctx, ex.lhs )
			if start_ty == nil do return nil, .Invalid

			// FIXME(rd): Encapsulate this in a consistent function
			if s_addr_mode == .Invalid {
				log_spanned_error( &ex.lhs.span, "range start expression is not a value" )
				return nil, .Invalid
			}

			if ty_is_untyped_builtin( start_ty ) {
				start_cast_ok := try_ellide_untyped_to_ty( ex.lhs, ty_builtin_isize )
				if !start_cast_ok {
					log_spanned_error( &ex.lhs.span, "untyped literal cannot be used to represent an isize" )
					return nil, .Invalid
				}

				start_ty = ex.lhs.type
			}

			if !ty_is_integer( start_ty ) {
				log_spanned_errorf( &ex.lhs.span, "expected an integer, got '{}'", start_ty.name )
				return nil, .Invalid
			}

			end_ty, e_addr_mode := tc_check_expr( ctx, ex.rhs )
			if end_ty == nil do return nil, .Invalid

			if e_addr_mode == .Invalid {
				log_spanned_error( &ex.rhs.span, "range end expression is not a value" )
				return nil, .Invalid
			}

			if ty_is_untyped_builtin( end_ty ) {
				end_cast_ok := try_ellide_untyped_to_ty( ex.rhs, ty_builtin_isize )
				if !end_cast_ok {
					log_spanned_error( &ex.lhs.span, "untyped literal cannot be used to represent an isize" )
					return nil, .Invalid
				}

				end_ty = ex.rhs.type
			}

			if !ty_is_integer( end_ty ) {
				log_spanned_errorf( &ex.rhs.span, "expected an integer, got '{}'", end_ty.name )
				return nil, .Invalid
			}

			ex.type = ty_builtin_range

			return ty_builtin_range, .RValue
		case ^UnaryOpExpr:
			rand_ty, addr_mode := tc_check_expr( ctx, ex.rand )
			if rand_ty == nil do return nil, .Invalid

			fnl_ty: ^Type
			fnl_addr_mode: AddressingMode

			#partial switch ex.op.kind {
				case .At:
					if addr_mode == .Invalid {
						log_spanned_error( &ex.rand.span, "expected value" )
						return nil, .Invalid
					}

					if !ty_is_pointer( rand_ty ) {
						log_spanned_errorf( &ex.rand.span, "expected pointer type, got '{}'", rand_ty.name )
						return nil, .Invalid
					}

					ptr_ty := rand_ty.derived.(^PointerType)
					base := ptr_ty.underlying

					ex.type = base

					fnl_ty = base
					fnl_addr_mode = .LValue
				case .Ampersand:
					if addr_mode != .LValue {
						log_spanned_error( &ex.rand.span, "expected addressable lvalue" )
						return nil, .Invalid
					}

					ptr_ty := new_type( PointerType, nil, "ptr (TODO)" )
					ptr_ty.underlying = rand_ty

					ex.type = ptr_ty

					fnl_ty = ptr_ty
					fnl_addr_mode = .RValue
				case .Bang:
					if addr_mode == .Invalid {
						log_spanned_error( &ex.rand.span, "expected value" )
						return nil, .Invalid
					}

					if !ty_is_bool( rand_ty ) {
						log_spanned_errorf( &ex.rand.span, "expected type 'bool' got '{}'", rand_ty.name )
						return nil, .Invalid
					}

					ex.type = ty_builtin_bool

					fnl_ty = ty_builtin_bool
					fnl_addr_mode = .RValue
				case .Tilde, .Minus:
					if addr_mode == .Invalid {
						log_spanned_error( &ex.rand.span, "expected value" )
						return nil, .Invalid
					}

					if !ty_is_integer( rand_ty ) {
						log_spanned_errorf( &ex.rand.span, "expected integer, got '{}'", rand_ty.name )
						return nil, .Invalid
					}

					ex.type = rand_ty

					fnl_ty = rand_ty
					fnl_addr_mode = .RValue
			}

			assert( fnl_ty != nil )

			return fnl_ty, fnl_addr_mode
		case ^BinOpExpr:
			lhs_ty, l_addr_mode := tc_check_expr( ctx, ex.lhs )
			if lhs_ty == nil do return nil, .Invalid

			rhs_ty, r_addr_mode := tc_check_expr( ctx, ex.rhs )
			if rhs_ty == nil do return nil, .Invalid

			if is_mutating_op( ex.op.kind ) {
				if l_addr_mode != .LValue {
					log_spanned_error( &ex.lhs.span, "expression does not produce an addressable value" )
					return nil, .Invalid
				}

				is_mut, offending_expr := is_mutable_lvalue( ctx, ex.lhs )
				if !is_mut {
					assert( offending_expr != nil )
					log_spanned_error( &offending_expr.span, "binding is not mutable" )
					return nil, .Invalid
				}
			}

			l_is_untyped := ty_is_untyped_builtin( lhs_ty )
			r_is_untyped := ty_is_untyped_builtin( rhs_ty )

			if l_is_untyped && r_is_untyped {
				ex.lhs.type = get_untyped_default_concrete_ty( ex.lhs.type )
				ex.rhs.type = get_untyped_default_concrete_ty( ex.rhs.type )
			} else if l_is_untyped && !r_is_untyped {
				_ = try_ellide_untyped_to_ty( ex.lhs, rhs_ty )
			} else if !l_is_untyped && r_is_untyped {
				_ = try_ellide_untyped_to_ty( ex.rhs, lhs_ty )
			}

			ty, ok := type_after_op( ex.op, ex.lhs.type, ex.rhs.type )
			if !ok {
				log_spanned_errorf( &ex.op.span, "operation not allowed between '{}' and '{}'", ex.lhs.type.name, ex.rhs.type.name )
				return nil, .Invalid
			}

			ex.type = ty
			return ty, .RValue
		case ^ProcCallExpr:
			decl := lookup_ident( ctx, ex.name )
			if decl == nil {
				log_spanned_errorf( &ex.span, "undeclared function '{}'", ex.name )
				return nil, .Invalid
			}

			fn_ty, is_fn := decl.type.derived.(^FnType)
			if !is_fn {
				log_spanned_errorf( &ex.span, "'{}' is not a function (maybe we need to implement generics now? otherwise, skill issue)", ex.name )
				return nil, .Invalid
			}

			if len( ex.params ) != len( fn_ty.params ) {
				log_spanned_errorf( &ex.span, "function '{}' takes {} parameters, got {}", ex.name, len( fn_ty.params ), len( ex.params ) )
				return nil, .Invalid
			}

			for i in 0..<len(ex.params) {
				param_ty, addr_mode := tc_check_expr( ctx, ex.params[i] )
				if param_ty == nil do return nil, .Invalid

				if addr_mode == .Invalid {
					log_spanned_error( &ex.span, "expected value" )
					return nil, .Invalid
				}

				if ty_is_untyped_builtin( param_ty ) {
					ok := try_ellide_untyped_to_ty( ex.params[i], fn_ty.params[i] )
					if !ok {
						log_spanned_errorf( &ex.params[i].span, "could not implicity cast '{}' to '{}'", ex.params[i].type.name, fn_ty.params[i].name )
						return nil, .Invalid
					}

					param_ty = ex.params[i].type
				}

				if !ty_eq(param_ty, fn_ty.params[i]) {
					log_spanned_errorf( &ex.span, "parameter type mismatch, expected '{}' got '{}'", fn_ty.params[i].name, param_ty.name )
					return nil, .Invalid
				}
			}

			ex.type = fn_ty.return_type

			return fn_ty.return_type, .RValue
		case ^PrimitiveTypeExpr:
			prim_ty: ^Type
			switch ex.prim {
				case .TypeID:
					prim_ty = ty_builtin_typeid
				case .Void:
					prim_ty = ty_builtin_void
				case .Bool:
					prim_ty = ty_builtin_bool
				case .U8:
					prim_ty = ty_builtin_u8
				case .I8:
					prim_ty = ty_builtin_i8
				case .U16:
					prim_ty = ty_builtin_u16
				case .I16:
					prim_ty = ty_builtin_i16
				case .U32:
					prim_ty = ty_builtin_u32
				case .I32:
					prim_ty = ty_builtin_i32
				case .U64:
					prim_ty = ty_builtin_u64
				case .I64:
					prim_ty = ty_builtin_i64
				case .USize:
					prim_ty = ty_builtin_usize
				case .ISize:
					prim_ty = ty_builtin_isize
				case .F32:
					prim_ty = ty_builtin_f32
				case .F64:
					prim_ty = ty_builtin_f64
				case .String:
					prim_ty = ty_builtin_string
				case .CString:
					prim_ty = ty_builtin_cstring
				case .RawPtr:
					prim_ty = ty_builtin_rawptr
				case .Range:
					prim_ty = ty_builtin_range
				case .UntypedInt:
					prim_ty = ty_builtin_untyped_int
				case .UntypedFloat:
					prim_ty = ty_builtin_untyped_float
				case .UntypedString:
					prim_ty = ty_builtin_untyped_string
			}

			ex.to_ty = prim_ty
			ex.type = ty_builtin_typeid
			return ex.type, .RValue
		case ^PointerTypeExpr:
			underlying_ty := tc_check_type( ctx, ex.base_type )
			if underlying_ty == nil do return nil, .Invalid

			ptr_ty := new_type( PointerType, nil, "ptr (TODO)" )
			ptr_ty.underlying = underlying_ty

			ex.to_ty = ptr_ty
			ex.type = ty_builtin_typeid
			return ex.type, .RValue
		case ^SliceTypeExpr:
			underlying_ty := tc_check_type( ctx, ex.base_type )
			if underlying_ty == nil do return nil, .Invalid

			slice_ty := new_type( SliceType, nil, "slice (TODO)" )
			slice_ty.underlying = underlying_ty

			ex.to_ty = slice_ty
			ex.type = ty_builtin_typeid
			return ex.type, .RValue
		case ^ArrayTypeExpr:
			log_spanned_error( &ex.span, "impl array type checking" )
			return nil, .Invalid
	}

	assert( false )

	return nil, .Invalid
}

is_mutable_lvalue_member_access :: proc( ctx: ^CheckerContext, m: ^MemberAccessExpr ) -> (bool, ^Expr)
{
	old_hint_ty := ctx.hint_type
	defer ctx.hint_type = old_hint_ty

	val := m.val
	val_ty := val.type
	is_mut_binding_ref :: proc(ctx: ^CheckerContext, ex: ^Expr) -> bool {
		#partial switch e in ex.derived_expr {
			// TODO(RD): Add array access expr when that's a thing
			case ^Ident:
				decl := lookup_ident(ctx, e.name)
				assert( decl != nil )
				#partial switch d in decl.derived_stmnt {
					case ^VarDecl:
						return d.is_mut
					case ^ConstDecl:
						return false
				}
		}
		return false
	}

	if !ty_is_mut_pointer( val_ty ) && !is_mut_binding_ref( ctx, val ) {
		return false, val
	}

	ctx.hint_type = val_ty
	child_member_access, is_child_member_access := m.member.derived_expr.(^MemberAccessExpr)

	for is_child_member_access {
		child_v_ty := child_member_access.val.type

		// TODO: Add case for slices once array access is implemented
		if ty_is_pointer( child_v_ty ) && !ty_is_mut_pointer( child_v_ty ) {
			return false, child_member_access.val
		}

		child_member_access, is_child_member_access = child_member_access.member.derived_expr.(^MemberAccessExpr)
	}

	return true, nil
}

is_mutable_lvalue_unary_op :: proc( ctx: ^CheckerContext, u: ^UnaryOpExpr ) -> (bool, ^Expr)
{
	return false, u
}

is_mutable_lvalue :: proc( ctx: ^CheckerContext, ex: ^Expr ) -> (bool, ^Expr)
{
	#partial switch e in ex.derived_expr {
		case ^Ident:
			decl := lookup_ident( ctx, e.name )
			assert( decl != nil )
			#partial switch d in decl.derived_stmnt {
				case ^VarDecl:
					return d.is_mut, e
				case ^ConstDecl:
					return false, e
			}
		case ^MemberAccessExpr:
			return is_mutable_lvalue_member_access( ctx, e )
		case ^UnaryOpExpr:
			return is_mutable_lvalue_unary_op( ctx, e )
	}

	return false, ex
}

is_bool_op :: proc( op: TokenKind ) -> bool
{
	#partial switch op {
		case .LAngle, .LessThanOrEqual, .RAngle, .GreaterThanOrEqual,
		     .Equal, .NotEqual:
			return true
	}

	return false
}

type_after_op :: proc( op: Token, l_ty: ^Type, r_ty: ^Type ) -> ( ^Type, bool )
{
	#partial switch op.kind {
		case .Plus, .Minus, .Star, .Slash, .Percent,
		     .LAngle, .LessThanOrEqual, .LShift,
		     .RAngle, .GreaterThanOrEqual, .RShift,
		     .Equal, .NotEqual, .Ampersand, .Pipe,
		     .Caret, .Assign, .PlusAssign, .MinusAssign,
		     .StarAssign, .SlashAssign, .PercentAssign:
			if !ty_is_number( l_ty ) || !ty_is_number( r_ty ) {
				return nil, false
			}

			if !ty_eq(l_ty, r_ty) {
				return nil, false
			}

			ret_ty := l_ty
			if is_bool_op( op.kind ) {
				ret_ty = ty_builtin_bool
			} else if is_mutating_op( op.kind ) {
				ret_ty = ty_builtin_void
			}

			_ = ret_ty

			return ret_ty, true
		case .DoubleAmpersand, .DoublePipe, .DoubleCaret:
			if !ty_is_bool( l_ty ) || !ty_is_bool( r_ty ) {
				return nil, false
			}

			return l_ty, true
		case .AmpersandAssign, .PipeAssign, .CaretAssign:
			if !( ty_is_number( l_ty ) && ty_is_number( r_ty ) ) && !( ty_is_bool( l_ty ) && ty_is_bool( r_ty ) ) {
				return nil, false
			}

			if !ty_eq(l_ty, r_ty) {
				return nil, false
			}

			return ty_builtin_void, true
		case:
			assert( false, "Internal Compiler Error: Unexpected operator token" )
	}

	return nil, false
}

is_mutating_op :: proc( op: TokenKind ) -> bool
{
	#partial switch op {
		case .Assign, .PlusAssign, .MinusAssign, .StarAssign,
		     .SlashAssign, .PercentAssign, .AmpersandAssign,
		     .PipeAssign, .CaretAssign:
			return true
	}

	return false
}

lookup_ident :: proc( ctx: ^CheckerContext, ident_name: string ) -> ^Stmnt
{
	sc := ctx.curr_scope

	if ctx.hint_type != nil {
		#partial switch t in ctx.hint_type.derived {
			case ^StructType:
				sc = t.ast_scope
			case ^EnumType:
				sc = t.ast_scope
			case ^UnionType:
				sc = t.ast_scope
		}
	}

	for sc != nil {
		if ident_name in sc.symbols {
			return sc.symbols[ident_name]
		}
		sc = sc.parent
	}
	return nil
}

AddressingMode :: enum
{
	Invalid,
	LValue,
	RValue,
}

CheckerContext :: struct
{
	checker: ^Checker,
	mod: ^Module,
	curr_proc: ^ProcProto,
	curr_scope: ^Scope,
	curr_loop: ^Expr,
	loop_body: ^epoch.Node,
	loop_exit: ^epoch.Node,
	addr_mode: AddressingMode,
	hint_type: ^Type,
	cg_fn: ^epoch.Function
}
