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
			case ^VarDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Redefinition of symbol '{:s}'", st.name )
					return false
				}

				s.symbols[st.name] = stmnt
			case ^EnumVariantDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Duplicate enum variant '{:s}'", st.name )
					return false
				}

				s.symbols[st.name] = stmnt
			case ^UnionVariantDecl:
				if st.name in s.symbols {
					log_spanned_errorf( &st.span, "Duplicate union variant '{:s}'", st.name )
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

	log_error( "impl check_pkg" )

	return .Error
}


CheckerContext :: struct
{
	checker: ^Checker,
	mod: ^Module,
	curr_proc: ^Scope,
	curr_scope: ^Scope,
	curr_loop: ^Stmnt,
}

