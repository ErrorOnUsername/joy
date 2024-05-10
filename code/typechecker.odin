package main

import "core:sync"
import "core:strings"
import "core:fmt"


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


Checker :: struct
{
	proc_work_mutex: sync.Mutex,
	proc_bodies:     [dynamic]^Scope,
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
		compiler_enqueue_work( .CheckProcBody, checker = c )
	}

	return compiler_finish_work()
}


pump_tc_check_proc_body :: proc( c: ^Checker, p: ^Scope ) -> PumpResult
{
	log_error( "impl check_proc_body" )
	return .Error
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
		ctx.defer_proc_bodies = true
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

			if s.value != nil {
				ty, addr_mode := tc_check_expr( ctx, s.value )
				if ty == nil do return false

				if addr_mode != .Value {
					log_spanned_error( &s.value.span, "Expression does produce a value" )
					return false
				}

				if s.type_hint != nil && s.type != ty {
					// FIXME(RD): Print type names (ie "Cannot assign value of type 'typename' to identifier of type 'other_typename'")
					log_spanned_error( &s.span, "Value assigned to identifier of incompatible type" )
					return false
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

			if s.default_value != nil {
				ty, addr_mode := tc_check_expr( ctx, s.default_value )
				if ty == nil do return false

				if addr_mode != .Value {
					log_spanned_error( &s.default_value.span, "Expression does not produce a value" )
					return false
				}

				if s.type != nil && s.type != ty {
					log_spanned_error( &s.span, "Value assigned to identifier of incompatible type" )
					return false
				}

				s.type = ty
			}

			assert( s.type_hint != nil || s.default_value != nil, "Internal Compiler Error: VarDecl must have at least a type hint or a default value" )

			ctx.curr_scope.symbols[s.name] = s
		case ^EnumVariantDecl:
			sc := ctx.curr_scope
			assert( sc.variant == .Enum, "Enum variant declared outside of enum scope" )

			s.type = ty_builtin_usize
		case ^UnionVariantDecl:
			log_spanned_error( &s.span, "impl union variant checking" )
			return false
		case ^ExprStmnt:
			ty, addr_mode := tc_check_expr( ctx, s.expr )
			if ty == nil do return false

			if addr_mode != .Value {
				log_spanned_error( &s.expr.span, "Expression does not produce a value" )
				return false
			}

			if !ty_is_void( ty ) {
				log_spanned_error( &s.span, "Expression produces a value, but that value is discarded. If this is intentional, consider assigning it to the discard identifier: '_'" )
			}
		case ^ContinueStmnt:
			if ctx.curr_loop != nil {
				log_spanned_error( &s.span, "'continue' statements are only prermitted within loops" )
				return false
			}
		case ^BreakStmnt:
			if ctx.curr_loop != nil {
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

			if addr_mode != .Value {
				log_spanned_error( &s.expr.span, "Expression does not produce a value" )
				return false
			}

			if ty != ctx.curr_proc.type {
				log_spanned_error( &s.span, "return expression's type does not match the return type of the function" )
			}
	}

	stmnt.check_state = .Resolved

	return true
}


tc_check_type :: proc( ctx: ^CheckerContext, type_expr: ^Expr ) -> ^Type
{
	ty, addr_mode := tc_check_expr( ctx, type_expr )
	if ty == nil do return nil

	if addr_mode != .Type {
		log_spanned_error( &type_expr.span, "Expression does not reference a type" )
		return nil
	}

	return ty
}


tc_check_expr :: proc( ctx: ^CheckerContext, expr: ^Expr ) -> (^Type, AddressingMode)
{
	switch ex in expr.derived_expr {
		case ^ProcProto:
			last_scope := ctx.curr_scope
			ctx.curr_scope = ex.body
			defer ctx.curr_scope = last_scope

			ty := new_type( FnType, ctx.mod )

			for p in ex.params {
				if p.name in ex.body.symbols {
					log_spanned_error( &p.span, "Redefinition of function parameter" )
					return nil, .Invalid
				}

				param_ok := tc_check_stmnt( ctx, p )
				if !param_ok do return nil, .Invalid

				append( &ty.params, p.type )

				ex.body.symbols[p.name] = p
			}

			if ex.return_type != nil {
				return_ty, addr_mode := tc_check_expr( ctx, ex.return_type )
				if return_ty == nil do return nil, .Invalid

				if addr_mode != .Type {
					log_spanned_error( &ex.return_type.span, "Expression does not reference a type" )
					return nil, .Invalid
				}

				ty.return_type = return_ty
			} else {
				ty.return_type = ty_builtin_void
			}

			ex.type = ty

			if ctx.defer_proc_bodies {
				log_error( "impl proc body deferring" )
				return nil, .Invalid
			} else {
				for stmnt in ex.body.stmnts {
					stmnt_ok := tc_check_stmnt( ctx, stmnt )
					if !stmnt_ok do return nil, .Invalid
				}
			}

			return ty, .Value if ex.body != nil else .Type
		case ^Ident:
			stmnt := lookup_ident( ctx, ex.name )
			if stmnt == nil {
				log_spanned_errorf( &ex.span, "Undeclared identifier '{}'", ex.name )
				return nil, .Invalid
			}

			if stmnt.check_state != .Resolved {
				stmnt_ok := tc_check_stmnt( ctx, stmnt )
				if !stmnt_ok do return nil, .Invalid
			}

			switch st in stmnt.derived_stmnt {
				case ^ConstDecl:
					val := st.value
					#partial switch v in val.derived_expr {
						case ^ProcProto:
							return st.type, .Value // function pointer
						case ^Scope:
							assert( v.variant != .Logic, "Logic scope assigned to constant" )
							assert( st.type != nil, "Statement doesn't have type" )
							return st.type, .Type
						case:
							return st.type, .Value
					}

				case ^EnumVariantDecl:
				case ^UnionVariantDecl:
					return st.type, .Type

				case ^VarDecl:
					return st.type, .Value

				case ^ExprStmnt:
				case ^ContinueStmnt:
				case ^BreakStmnt:
				case ^ReturnStmnt:
					panic( "Internal Compiler Error: Identifer references bindless statement" )
			}

			return nil, .Invalid
		case ^StringLiteralExpr:
			ex.type = ty_builtin_untyped_string
			return ex.type, .Value
		case ^NumberLiteralExpr:
			log_spanned_error( &ex.span, "impl number literal checking" )
			return nil, .Invalid
		case ^NamedStructLiteralExpr:
			log_spanned_error( &ex.span, "impl struct literal checking" )
			return nil, .Invalid
		case ^AnonStructLiteralExpr:
			log_spanned_error( &ex.span, "impl struct literal checking" )
			return nil, .Invalid
		case ^MemberAccessExpr:
			log_spanned_error( &ex.span, "impl member access checking" )
			return nil, .Invalid
		case ^ImplicitSelectorExpr:
			log_spanned_error( &ex.span, "impl implicit selector checking" )
			return nil, .Invalid
		case ^Scope:
			last_scope := ctx.curr_scope
			ctx.curr_scope = ex
			defer ctx.curr_scope = last_scope;

			switch ex.variant {
				case .Struct:
					struct_type := new_type( StructType, ctx.mod )
					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid

						append( &struct_type.members, m.type )
					}

					ex.type = struct_type
					return struct_type, .Value
				case .Union:
					union_type := new_type( UnionType, ctx.mod )

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid

						struct_ty, is_struct := m.type.derived.(^StructType)
						if !is_struct {
							log_spanned_error( &m.span, "Union variant must be a struct type" )
							return nil, .Invalid
						}

						append( &union_type.variants, struct_ty )
					}

					ex.type = union_type
					return union_type, .Value
				case .Enum:
					enum_type := new_type( EnumType, ctx.mod )
					enum_type.underlying = ty_builtin_usize

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid
					}

					ex.type = enum_type
					return enum_type, .Value
				case .Logic:
					ex.type = ty_builtin_void

					for m in ex.stmnts {
						mem_ok := tc_check_stmnt( ctx, m )
						if !mem_ok do return nil, .Invalid
					}

					return ex.type, .Value
			}
		case ^IfExpr:
			log_spanned_error( &ex.span, "impl if checking" )
			return nil, .Invalid
		case ^ForLoop:
			log_spanned_error( &ex.span, "impl for checking" )
			return nil, .Invalid
		case ^WhileLoop:
			log_spanned_error( &ex.span, "impl while checking" )
			return nil, .Invalid
		case ^InfiniteLoop:
			log_spanned_error( &ex.span, "impl loop checking" )
			return nil, .Invalid
		case ^RangeExpr:
			log_spanned_error( &ex.span, "impl range checking" )
			return nil, .Invalid
		case ^UnaryOpExpr:
			log_spanned_error( &ex.span, "impl unary op checking" )
			return nil, .Invalid
		case ^BinOpExpr:
			log_spanned_error( &ex.span, "impl binary op checking" )
			return nil, .Invalid
		case ^ProcCallExpr:
			log_spanned_error( &ex.span, "impl proc call checking" )
			return nil, .Invalid
		case ^FieldAccessExpr:
			log_spanned_error( &ex.span, "impl field access checking" )
			return nil, .Invalid
		case ^PrimitiveTypeExpr:
			prim_ty: ^Type
			switch ex.prim {
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
					prim_ty = ty_builtin_untyped_string
				case .UntypedString:
					prim_ty = ty_builtin_untyped_string
			}

			ex.type = prim_ty
			return prim_ty, .Type
		case ^PointerTypeExpr:
			underlying_ty := tc_check_type( ctx, ex.base_type )
			if underlying_ty == nil do return nil, .Invalid

			ptr_ty := new_type( PointerType, nil )
			ptr_ty.underlying = underlying_ty

			ex.type = ptr_ty
			return ptr_ty, .Type
		case ^SliceTypeExpr:
			underlying_ty := tc_check_type( ctx, ex.base_type )
			if underlying_ty == nil do return nil, .Invalid

			slice_ty := new_type( SliceType, nil )
			slice_ty.underlying = underlying_ty

			ex.type = slice_ty
			return slice_ty, .Type
		case ^ArrayTypeExpr:
			log_spanned_error( &ex.span, "impl array type checking" )
			return nil, .Invalid
	}

	log_spanned_error( &expr.span, "impl check_expr" )
	return nil, .Invalid
}

lookup_ident :: proc( ctx: ^CheckerContext, ident_name: string ) -> ^Stmnt
{
	sc := ctx.curr_scope
	for sc != nil {
		if ident_name in sc.symbols {
			return sc.symbols[ident_name]
		}
		sc = sc.parent
	}
	return nil
}


CheckerContext :: struct
{
	checker: ^Checker,
	mod: ^Module,
	defer_proc_bodies: bool,
	curr_proc: ^Scope,
	curr_scope: ^Scope,
	curr_loop: ^Stmnt,
	addr_mode: AddressingMode,
}
