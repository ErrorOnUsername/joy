package main

import "core:strings"
import "core:fmt"


checker_cycle_check_rec :: proc( pkg: ^Package, cycle_checker: ^[dynamic]^Package ) -> ( found_cycle := false, cycle_report := "<none>" )
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
        p_found_cycle, rep := checker_cycle_check_rec( p, cycle_checker )
        if p_found_cycle do return p_found_cycle, rep
    }

    pop( cycle_checker )

    return
}


checker_does_import_graph_contiain_cycles :: proc( root_pkg: ^Package ) -> ( found_cycle: bool, cycle_report: string )
{
    cycle_checker := make( [dynamic]^Package )
    defer delete( cycle_checker )

    found_cycle, cycle_report = checker_cycle_check_rec( root_pkg, &cycle_checker )
    if found_cycle do return found_cycle, cycle_report

    return
}


checker_build_graph_dag_topo :: proc( prio: ^int, list: ^[dynamic]PriorityItem( ^Package ), pkg: ^Package )
{
    for parent in pkg.imports {
        if prio^ != 0 {
            prio^ -= 1
        }

        checker_build_graph_dag_topo( prio, list, parent )
    }

    append( list, PriorityItem( ^Package ) { prio^, pkg } )

    prio^ += 1
}


checker_build_package_list :: proc( root_pkg: ^Package ) -> ( []PriorityItem( ^Package ), bool )
{
    contains_cycles, first_cycle := checker_does_import_graph_contiain_cycles( root_pkg )
    if contains_cycles {
        log_errorf( "Package import graph contains cycles: {}", first_cycle )
        return nil, false
    }

    prio := 0
    list := make( [dynamic]PriorityItem( ^Package ) )
    checker_build_graph_dag_topo( &prio, &list, root_pkg )

    return list[:], true
}


checker_initialize_symbol_tables :: proc( pkgs: []PriorityItem( ^Package ) ) -> bool
{
    for pkg in pkgs {
        for mod in pkg.item.modules {
            ok := checker_initialize_symbol_tables_for_scope( mod.file_scope )
            if !ok do return false
        }
    }

    return true
}


checker_initialize_symbol_tables_for_scope :: proc( s: ^Scope ) -> bool
{
    s.symbols = make( map[string]Node )

    for stmnt in s.stmnts {
        switch st in stmnt.derived_stmnt {
            case ^StructDecl:
                if st.name in s.symbols {
                    log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
                    return false
                }

                s.symbols[st.name] = st
            case ^EnumDecl:
                if st.name in s.symbols {
                    log_spanned_errorf( &st.span, "Redefinition of identifier '{}'", st.name )
                    return false
                }

                s.symbols[st.name] = st
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

                body_ok := checker_initialize_symbol_tables_for_scope( st.body )
                if !body_ok do return false
            case ^VarDecl: // igonred until real checking starts...
            case ^ExprStmnt: // igonred until real checking starts...
            case ^BlockStmnt:
                block_ok := checker_initialize_symbol_tables_for_scope( st.scope )
                if !block_ok do return false
            case ^ContinueStmnt: // igonred until real checking starts...
            case ^BreakStmnt: // igonred until real checking starts...
            case ^IfStmnt:
                curr_if := st
                for curr_if != nil {
                    body_ok := checker_initialize_symbol_tables_for_scope( curr_if.then_block )
                    if !body_ok do return false

                    curr_if = curr_if.else_stmnt
                }
            case ^ForLoop:
                body_ok := checker_initialize_symbol_tables_for_scope( st.body )
                if !body_ok do return false
            case ^WhileLoop:
                body_ok := checker_initialize_symbol_tables_for_scope( st.body )
                if !body_ok do return false
            case ^InfiniteLoop:
                body_ok := checker_initialize_symbol_tables_for_scope( st.body )
                if !body_ok do return false
        }
    }

    return true
}


checker_collect_proc_signatures :: proc( pkgs: []PriorityItem( ^Package ) )
{
    for pkg in pkgs {
        for mod in pkg.item.modules {
            checker_collect_proc_sigs_in_scope( mod.file_scope )
        }
    }
}


checker_collect_proc_sigs_in_scope :: proc( s: ^Scope )
{
    for stmnt in s.stmnts {
        #partial switch st in stmnt.derived_stmnt {
            case ^ProcDecl:
        }
    }
}


CheckerContext :: struct
{
}


pump_checker_check_module :: proc( file_id: FileID ) -> PumpResult
{
    mod_data := fm_get_data( file_id )
    if mod_data.is_dir {
        log_errorf( "Tried to check module '{}' but it is actually a package", mod_data.rel_path )
        return .Error
    }

    if mod_data.mod == nil {
        log_errorf( "Tried to typecheck module '{}' that hasn't been parsed yet", mod_data.rel_path )
        return .Error
    }

    ctx: CheckerContext

    ok := checker_check_scope( &ctx, mod_data.mod.file_scope )
    if !ok do return .Error

    return .Continue
}


checker_check_scope :: proc( ctx: ^CheckerContext, s: ^Scope ) -> bool
{
    log_error( "impl checker_check_scope" )
    return false
}
