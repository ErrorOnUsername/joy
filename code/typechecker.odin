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
	type_def_mtx: sync.Mutex,
	type_defs:   [dynamic]^Stmnt,
	proc_def_mtx: sync.Mutex,
	proc_defs: [dynamic]^ProcDecl,
}


tc_initialize_scopes :: proc( c: ^Checker, pkgs: []PriorityItem( ^Package ) ) -> int
{
	for pkg in pkgs {
		for mod in pkg.item.modules {
			compiler_enqueue_work( .InitializeScopes, mod.file_id, c )
		}
	}

	failed_tasks := compiler_finish_work()
	return failed_tasks
}


pump_tc_init_scopes :: proc( file_id: FileID, c: ^Checker ) -> PumpResult
{
	data := fm_get_data( file_id )
	ok := tc_initialize_in_scope( c, data.mod.file_scope )
	if !ok do return .Error

	return .Continue
}


tc_initialize_in_scope :: proc( c: ^Checker, s: ^Scope ) -> bool
{
	s.symbols = make( SymbolTable )

	for stmnt in s.stmnts {
		switch st in stmnt.derived_stmnt {
			case ^StructDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
					return false
				}

				s.symbols[st.name] = st

				st.memb_lookup = make( SymbolTable )
				for m in st.members {
					if m.name in st.memb_lookup {
						log_spanned_errorf( &m.span, "Redefinition of struct member '{}'", m.name )
						return false
					}

					st.memb_lookup[m.name] = m
				}
			case ^EnumVariant:
			case ^EnumDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
					return false
				}

				s.symbols[st.name] = st

				st.vari_lookup = make( SymbolTable )
				for v in st.variants {
					if v.name in st.vari_lookup {
						log_spanned_errorf( &v.span, "Redefinition of enum variant '{}'", v.name )
						return false
					}

					st.vari_lookup[v.name] = v
				}
			case ^UnionDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
					return false
				}

				s.symbols[st.name] = st
			case ^ProcDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
					return false
				}

				s.symbols[st.name] = st

				body_ok := tc_initialize_in_scope( c, st.body )
				if !body_ok do return false
			case ^VarDecl: // igonred until real checking starts...
			case ^ExprStmnt: // igonred until real checking starts...
			case ^BlockStmnt:
				block_ok := tc_initialize_in_scope( c, st.scope )
				if !block_ok do return false
			case ^ContinueStmnt: // igonred until real checking starts...
			case ^BreakStmnt: // igonred until real checking starts...
			case ^IfStmnt:
				curr_if := st
				for curr_if != nil {
					body_ok := tc_initialize_in_scope( c, st.then_block )
					if !body_ok do return false

					curr_if = curr_if.else_stmnt
				}
			case ^ForLoop:
				body_ok := tc_initialize_in_scope( c, st.body )
				if !body_ok do return false
			case ^WhileLoop:
				body_ok := tc_initialize_in_scope( c, st.body )
				if !body_ok do return false
			case ^InfiniteLoop:
				body_ok := tc_initialize_in_scope( c, st.body )
				if !body_ok do return false
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

		compiler_enqueue_work( .CheckPackage, 0, c, pkg.item )
	}
	tasks_failed = compiler_finish_work()

	return tasks_failed
}


pump_tc_check_pkg :: proc( c: ^Checker, pkg: ^Package ) -> PumpResult
{
	// Single-threadedly check top level declarations of the
	// package and queue up procedure bodies to be checked
	// in parallel
	ok := true

	ctx: CheckerContext

	for mod in &pkg.modules {
		if !ok do break

		ctx.mod        = mod
		ctx.curr_scope = mod.file_scope

		for stmnt in mod.file_scope.stmnts {
			if !ok do break

			if stmnt.check_state == .Resolved do continue

			#partial switch st in stmnt.derived_stmnt {
				case ^StructDecl, ^EnumDecl, ^UnionDecl, ^ProcDecl:
					ok = tc_check_type_decl( &ctx, stmnt )
				case:
					log_spanned_error( &stmnt.span, "Unexpected top-level declaration" )
					ok = false
			}
		}
	}

	return .Continue if ok else .Error
}


CheckerContext :: struct
{
	mod: ^Module,
	curr_proc: ^ProcDecl,
	curr_scope: ^Scope,
	curr_loop: ^Stmnt,
	type_hint: ^Type,
}


tc_check_scope :: proc( ctx: ^CheckerContext, sc: ^Scope ) -> bool
{
	prev_scope := ctx.curr_scope
	defer ctx.curr_scope = prev_scope

	ctx.curr_scope = sc

	for stmnt in sc.stmnts {
		ok := true
		switch st in stmnt.derived_stmnt {
			case ^StructDecl, ^EnumDecl, ^UnionDecl, ^ProcDecl:
				ok = tc_check_type_decl( ctx, stmnt )
			case ^EnumVariant:
				log_spanned_error( &st.span, "got scope-level enum variant somehow?" )
				ok = false
			case ^VarDecl:       ok = tc_check_var_decl( ctx, st )
			case ^ExprStmnt:     ok = tc_check_expr_stmnt( ctx, st )
			case ^BlockStmnt:    ok = tc_check_block_stmnt( ctx, st )
			case ^ContinueStmnt: ok = tc_check_continue_stmnt( ctx, st )
			case ^BreakStmnt:    ok = tc_check_break_stmnt( ctx, st )
			case ^IfStmnt:       ok = tc_check_if_stmnt( ctx, st )
			case ^ForLoop:       ok = tc_check_for_loop( ctx, st )
			case ^WhileLoop:     ok = tc_check_while_loop( ctx, st )
			case ^InfiniteLoop:  ok = tc_check_inf_loop( ctx, st )
		}

		if !ok do return false
	}

	return true
}


tc_check_type_decl :: proc( ctx: ^CheckerContext, s: ^Stmnt ) -> bool
{
	#partial switch d in s.derived_stmnt {
		case ^StructDecl: return tc_check_struct_decl( ctx, d )
		case ^EnumDecl:   return tc_check_enum_decl( ctx, d )
		case ^UnionDecl:  return tc_check_union_decl( ctx, d )
		case ^ProcDecl:   return tc_check_proc_decl( ctx, d )
		case:
			log_spanned_error( &s.span, "Got unexpected type declaration" )
	}

	return false
}


tc_check_type :: proc( ctx: ^CheckerContext, t_expr: ^Expr ) -> bool
{
	log_spanned_error( &t_expr.span, "impl check_type" )
	return false
}


tc_check_struct_decl :: proc( ctx: ^CheckerContext, d: ^StructDecl ) -> bool
{
	if d.check_state == .Resolved do return true

	final_ty := new_type( StructType, ctx.mod )
	final_ty.decl = d

	for member in d.members {
		if member.default_value != nil {
			log_spanned_error( &member.default_value.span, "struct default values are not supported" )
			return false
		}

		if member.type_hint == nil {
			log_spanned_error( &member.span, "struct members must specify a type" )
			return false
		}

		hint_ok := tc_check_type( ctx, member.type_hint )
		if !hint_ok do return false

		member.type = member.type_hint.type
	}

	d.type        = final_ty
	d.check_state = .Resolved

	return true
}


tc_check_enum_decl :: proc( ctx: ^CheckerContext, d: ^EnumDecl ) -> bool
{
	if d.check_state == .Resolved do return true

	final_ty := new_type( EnumType, ctx.mod )
	final_ty.decl = d

	if d.type_hint == nil {
		d.underlying = ty_builtin_usize
	} else {
		ty_ok := tc_check_type( ctx, d.type_hint )
		if !ty_ok do return false

		if !ty_is_int( d.type_hint.type ) {
			log_spanned_error( &d.type_hint.span, "enum underlying type must be an integer" )
			return false
		}

		d.underlying = d.type_hint.type
	}

	for var in d.variants {
		vari_ok := tc_check_enum_variant( ctx, var )
		if !vari_ok do return false
	}

	d.type        = final_ty
	d.check_state = .Resolved

	return true
}


tc_check_enum_variant :: proc( ctx: ^CheckerContext, v: ^EnumVariant ) -> bool
{
	v.type = v.owning_enum.underlying
	return true
}


tc_check_union_decl :: proc( ctx: ^CheckerContext, d: ^UnionDecl ) -> bool
{
	log_spanned_error( &d.span, "impl check_union_decl" )
	return false
}


tc_check_proc_decl :: proc( ctx: ^CheckerContext, d: ^ProcDecl ) -> bool
{
	if d.check_state == .Resolved do return true

	final_ty := new_type( ProcType, ctx.mod )
	final_ty.decl = d

	for param in d.params {
		if param.name in d.body.symbols {
			log_spanned_error( &param.span, "duplicate declaration of parameter" )
			return false
		}

		suggested_type: ^Type
		val_type: ^Type

		if param.type_hint != nil {
			hint_ok := tc_check_type( ctx, param.type_hint )
			if !hint_ok do return false

			suggested_type = param.type_hint.type
		}

		if param.default_value != nil {
			val_ok := tc_check_expr( ctx, param.default_value )
			if !val_ok do return false

			val_type = param.default_value.type
		}

		if suggested_type != nil && val_type != nil {
			if !ty_are_eq( suggested_type, val_type ) {
				log_spanned_error( &param.span, "mismatched types" ) // TODO: Make a better error for this
				return false
			}

			param.type = suggested_type
		} else {
			assert( suggested_type != nil || val_type != nil )

			param.type = suggested_type if suggested_type != nil else val_type
		}
	}

	d.type        = final_ty
	d.check_state = .Resolved

	return true
}


tc_check_var_decl :: proc( ctx: ^CheckerContext, d: ^VarDecl ) -> bool
{
	if d.check_state == .Resolved do return true

	sc := ctx.curr_scope

	if d.name in sc.symbols {
		log_spanned_error( &d.span, "duplicate declaration of identifier" )
		return false
	}

	sc.symbols[d.name] = d

	suggested_type: ^Type
	val_type: ^Type

	if d.type_hint != nil {
		hint_ok := tc_check_type( ctx, d.type_hint )
		if !hint_ok do return false

		suggested_type = d.type_hint.type
	}

	if d.default_value != nil {
		val_ok := tc_check_expr( ctx, d.default_value )
		if !val_ok do return false

		val_type = d.default_value.type
	}

	if suggested_type != nil && val_type != nil {
		if !ty_are_eq( suggested_type, val_type ) {
			log_spanned_error( &d.span, "mismatched types" ) // TODO: Make a better error for this
			return false
		}

		d.type = suggested_type
	} else {
		assert( suggested_type != nil || val_type != nil )

		d.type = suggested_type if suggested_type != nil else val_type
	}

	d.check_state = .Resolved

	return true
}


tc_check_expr_stmnt :: proc( ctx: ^CheckerContext, s: ^ExprStmnt ) -> bool
{
	log_spanned_error( &s.span, "impl check_expr_stmnt" )
	return false
}


tc_check_block_stmnt :: proc( ctx: ^CheckerContext, s: ^BlockStmnt ) -> bool
{
	log_spanned_error( &s.span, "impl check_block_stmnt" )
	return false
}


tc_check_continue_stmnt :: proc( ctx: ^CheckerContext, s: ^ContinueStmnt ) -> bool
{
	return ctx.curr_loop != nil
}


tc_check_break_stmnt :: proc( ctx: ^CheckerContext, s: ^BreakStmnt ) -> bool
{
	return ctx.curr_loop != nil
}


tc_check_if_stmnt :: proc( ctx: ^CheckerContext, s: ^IfStmnt ) -> bool
{
	log_spanned_error( &s.span, "impl check_if_stmnt" )
	return false
}


tc_check_for_loop :: proc( ctx: ^CheckerContext, l: ^ForLoop ) -> bool
{
	log_spanned_error( &l.span, "impl check_for_loop" )
	return false
}


tc_check_while_loop :: proc( ctx: ^CheckerContext, l: ^WhileLoop ) -> bool
{
	log_spanned_error( &l.span, "impl check_while_loop" )
	return false
}


tc_check_inf_loop :: proc( ctx: ^CheckerContext, l: ^InfiniteLoop ) -> bool
{
	log_spanned_error( &l.span, "impl check_inf_loop" )
	return false
}


tc_check_expr :: proc( ctx: ^CheckerContext, ex: ^Expr ) -> bool
{
	switch e in ex.derived_expr {
		case ^Ident:             return tc_check_ident( ctx, e )
		case ^StringLiteralExpr: return tc_check_string_lit( ctx, e )
		case ^NumberLiteralExpr: return tc_check_number_lit( ctx, e )
		case ^RangeExpr:         return tc_check_range_expr( ctx, e )
		case ^BinOpExpr:         return tc_check_bin_op_expr( ctx, e )
		case ^ProcCallExpr:      return tc_check_proc_call( ctx, e )
		case ^FieldAccessExpr:   return tc_check_field_access( ctx, e )
		case ^PointerTypeExpr:   unreachable()
		case ^ArrayTypeExpr:     unreachable()
		case ^SliceTypeExpr:     unreachable()
	}

	return true
}


tc_check_ident :: proc( ctx: ^CheckerContext, i: ^Ident ) -> bool
{
	log_spanned_error( &i.span, "impl check_ident" )
	return false
}


tc_check_string_lit :: proc( ctx: ^CheckerContext, s: ^StringLiteralExpr ) -> bool
{
	s.type = ty_builtin_untyped_string
	return true
}


tc_check_number_lit :: proc( ctx: ^CheckerContext, n: ^NumberLiteralExpr ) -> bool
{
	n.type = ty_builtin_untyped_int
	return true
}


tc_check_range_expr :: proc( ctx: ^CheckerContext, r: ^RangeExpr ) -> bool
{
	log_spanned_error( &r.span, "impl check_range_expr" )
	return false
}


tc_check_bin_op_expr :: proc( ctx: ^CheckerContext, b: ^BinOpExpr ) -> bool
{
	log_error( "impl check_bin_op_expr" )
	return false
}


tc_check_proc_call :: proc ( ctx: ^CheckerContext, b: ^ProcCallExpr ) -> bool
{
	log_error( "impl check_proc_call" )
	return false
}


tc_check_field_access :: proc( ctx: ^CheckerContext, f: ^FieldAccessExpr ) -> bool
{
	log_error( "impl check_field_access" );
	return false
}


lookup_identifier :: proc( ctx: ^CheckerContext, ident: string ) -> ^Stmnt
{
	s := ctx.curr_scope
	for s != nil {
		if ident in s.symbols {
			return s.symbols[ident]
		}

		s = s.parent
	}

	return nil
}

