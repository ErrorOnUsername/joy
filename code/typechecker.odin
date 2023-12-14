package main

import "core:container/queue"
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
	types: queue.Queue(^Stmnt),
	procs: queue.Queue(^ProcDecl),
}


tc_initialize :: proc( c: ^Checker, pkgs: []PriorityItem( ^Package ) ) -> bool
{
	for pkg in pkgs {
		for mod in pkg.item.modules {
			ok := tc_initialize_in_scope( c, mod.file_scope )
			if !ok do return false
		}
	}

	return true
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


CheckerContext :: struct
{
	mod: ^Module,
	curr_proc: ^ProcDecl,
	curr_scope: ^Scope,
	curr_loop: ^Stmnt,
	type_hint: ^Type,
}


tc_check_all :: proc( c: ^Checker ) -> bool
{
	// Check all types first
	log_error( "impl check_all" )
	return false
}


tc_check_scope :: proc( ctx: ^CheckerContext, sc: ^Scope ) -> bool
{
	prev_scope := ctx.curr_scope
	defer ctx.curr_scope = prev_scope

	ctx.curr_scope = sc

	for stmnt in sc.stmnts {
		ok := true
		switch st in stmnt.derived_stmnt {
			case ^StructDecl:    ok = tc_check_struct_decl( ctx, st )
			case ^EnumDecl:      ok = tc_check_enum_decl( ctx, st )
			case ^EnumVariant:   ok = tc_check_enum_variant( ctx, st )
			case ^UnionDecl:     ok = tc_check_union_decl( ctx, st )
			case ^ProcDecl:      ok = tc_check_proc_decl( ctx, st )
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


tc_check_struct_decl :: proc( ctx: ^CheckerContext, d: ^StructDecl ) -> bool
{
	for mem in d.members {
		if mem.default_value != nil {
			log_spanned_error( &mem.span, "impl checking structs with default values" )
			return false
		}

		ty := lookup_type( ctx.curr_scope, mem.type )
		if ty == nil {
			log_spanned_error( &mem.span, "struct member uses unknown type" )
			return false
		}

		mem.type = ty
	}

	return true
}


tc_check_enum_decl :: proc( ctx: ^CheckerContext, d: ^EnumDecl ) -> bool
{
	if d.type == nil {
		d.type = ty_builtin_usize
	}

	is_int_ty := ty_is_int( d.type )
	if !is_int_ty {
		log_spanned_error( &d.span, "enum base type must be an integer" )
	}

	vari_count := len( d.variants )
	does_var_count_fit := ty_does_int_fit_in_type( d.type.derived.(^PrimitiveType), vari_count )
	if !does_var_count_fit {
		log_spanned_error( &d.span, "enum variants don't fit in base type" )
		return false
	}

	return true
}


tc_check_enum_variant :: proc( ctx: ^CheckerContext, v: ^EnumVariant ) -> bool
{
	v.type = v.owning_enum.type
	return true
}


tc_check_union_decl :: proc( ctx: ^CheckerContext, d: ^UnionDecl ) -> bool
{
	log_error( "impl check_union_decl" )
	return false
}


tc_check_proc_decl :: proc( ctx: ^CheckerContext, d: ^ProcDecl ) -> bool
{
	prev_proc := ctx.curr_proc
	defer ctx.curr_proc = prev_proc

	ctx.curr_proc = d

	for p in d.params {
		if p.name in d.body.symbols {
			log_spanned_errorf( &p.span, "procedure has duplicate definitions of parameter: '{}'", p.name );
			return false
		}

		d.body.symbols[p.name] = p
	}

	if d.body != nil {
		body_ok := tc_check_scope( ctx, d.body )
		if !body_ok do return false
	}

	return true
}


tc_check_var_decl :: proc( ctx: ^CheckerContext, d: ^VarDecl ) -> bool
{
	sc := ctx.curr_scope
	if d.name in sc.symbols {
		log_spanned_errorf( &d.span, "redefinition of identifier '{}'", d.name )
		return false
	}

	if d.type != nil {
		ty := lookup_type( sc, d.type )
		if ty == nil {
			log_spanned_error( &d.span, "varable declared with unknown type" )
			return false
		}

		d.type = ty
	}

	if d.default_value != nil {
		val_ok := tc_check_expr( ctx, d.default_value )
		if !val_ok do return false

		if d.type == nil {
			if d.default_value.type == ty_builtin_untyped_string {
				d.type = ty_builtin_string
			} else if d.default_value.type == ty_builtin_untyped_int {
				d.type = ty_builtin_isize // TODO: verify int fits in isize
			} else {
				d.type = d.default_value.type
			}
		} else if !ty_are_eq( d.type, d.default_value.type ) {
			log_spanned_error( &d.span, "mismatched types! expression's type doesn't match declaration's type" )
			return false
		}
	}

	sc.symbols[d.name] = d
	return true
}


tc_check_expr_stmnt :: proc( ctx: ^CheckerContext, s: ^ExprStmnt ) -> bool
{
	expr_ok := tc_check_expr( ctx, s.expr )
	return expr_ok
}


tc_check_block_stmnt :: proc( ctx: ^CheckerContext, s: ^BlockStmnt ) -> bool
{
	block_ok := tc_check_scope( ctx, s.scope )
	return block_ok
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
	cond_ok := tc_check_expr( ctx, s.cond )
	if !cond_ok do return false

	if s.cond.type != ty_builtin_bool {
		log_spanned_error( &s.cond.span, "condition expression does not evaluate to 'bool'" )
		return false
	}

	then_block_ok := tc_check_scope( ctx, s.then_block )
	if !then_block_ok do return false

	if s.else_stmnt != nil {
		else_chain_ok := tc_check_if_stmnt( ctx, s.else_stmnt )
		if !else_chain_ok do return false
	}

	return false
}


tc_check_for_loop :: proc( ctx: ^CheckerContext, l: ^ForLoop ) -> bool
{
	prev_loop := ctx.curr_loop
	defer ctx.curr_loop = prev_loop

	ctx.curr_loop = l

	range_expr_ok := tc_check_expr( ctx, l.range )
	if !range_expr_ok do return false

	if l.range.type != ty_builtin_range {
		log_spanned_error( &l.range.span, "range expression of for loop does not resolve to type 'range'" )
		return false
	}

	body_ok := tc_check_scope( ctx, l.body )
	if !body_ok do return false

	return true
}


tc_check_while_loop :: proc( ctx: ^CheckerContext, l: ^WhileLoop ) -> bool
{
	prev_loop := ctx.curr_loop
	defer ctx.curr_loop = prev_loop

	ctx.curr_loop = l

	cond_ok := tc_check_expr( ctx, l.cond )
	if !cond_ok do return false

	if l.cond.type != ty_builtin_bool {
		log_spanned_error( &l.cond.span, "condition expression does not evaluate to 'bool'" )
		return false
	}

	body_ok := tc_check_scope( ctx, l.body )
	if !body_ok do return false

	return true
}


tc_check_inf_loop :: proc( ctx: ^CheckerContext, l: ^InfiniteLoop ) -> bool
{
	prev_loop := ctx.curr_loop
	defer ctx.curr_loop = prev_loop

	ctx.curr_loop = l

	body_ok := tc_check_scope( ctx, l.body )
	if !body_ok do return false

	return true
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
	n := lookup_identifier( ctx, i )
	if n == nil {
		log_spanned_error( &i.span, "use of undeclared identifier" )
		return false
	}

	i.type = n.type
	i.ref = n

	return true
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
	left_ok := tc_check_expr( ctx, r.lhs )
	if !left_ok do return false

	if r.lhs.type != ty_builtin_isize {
		log_spanned_error( &r.lhs.span, "range start expression does not evaluate to 'isize'" )
		return false
	}

	right_ok := tc_check_expr( ctx, r.rhs )
	if !right_ok do return false

	if r.rhs.type != ty_builtin_isize {
		log_spanned_error( &r.rhs.span, "range end expression does not evaluate to 'isize'" )
		return false
	}

	r.type = ty_builtin_range

	return true
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


lookup_identifier :: proc( ctx: ^CheckerContext, i: ^Ident ) -> ^Stmnt
{
	s := ctx.curr_scope
	for s != nil {
		if i.name in s.symbols {
			return s.symbols[i.name]
		}

		s = s.parent
	}

	return nil
}


lookup_type :: proc( s: ^Scope, t: ^Type ) -> ^Type
{
	_ = s
	return nil
}

