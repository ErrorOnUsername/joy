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


checker_collect_proc_signatures :: proc( pkgs: []PriorityItem( ^Package ) ) -> bool
{
    for pkg in pkgs {
        for mod in pkg.item.modules {
            res := checker_collect_proc_sigs_in_scope( mod.file_scope )
            if !res do return false
        }
    }

    return true
}


checker_collect_proc_sigs_in_scope :: proc( s: ^Scope ) -> bool
{
    for stmnt in s.stmnts {
        #partial switch st in stmnt.derived_stmnt {
            case ^ProcDecl:
                for p in st.params {
                    if p.type == nil || p.default_value != nil {
                        log_spanned_error( &p.default_value.span, "impl default arg checking in proc collection" )
                        return false
                    }

                    ty := lookup_type( s, p.type )
                    if ty == nil {
                        log_spanned_error( &p.span, "procedure parameter uses unknown type" )
                        return false
                    }

                    p.type = ty // This could leak memory... fix that lol
                }
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
    ctx.mod = mod_data.mod

    ok := checker_check_scope( &ctx, mod_data.mod.file_scope )
    if !ok do return .Error

    return .Continue
}


checker_check_scope :: proc( ctx: ^CheckerContext, sc: ^Scope ) -> bool
{
    prev_scope := ctx.curr_scope
    defer ctx.curr_scope = prev_scope

    ctx.curr_scope = sc

    for stmnt in sc.stmnts {
        ok := true
        switch st in stmnt.derived_stmnt {
            case ^StructDecl:    ok = checker_check_struct_decl( ctx, st )
            case ^EnumDecl:      ok = checker_check_enum_decl( ctx, st )
            case ^UnionDecl:     ok = checker_check_union_decl( ctx, st )
            case ^ProcDecl:      ok = checker_check_proc_decl( ctx, st )
            case ^VarDecl:       ok = checker_check_var_decl( ctx, st )
            case ^ExprStmnt:     ok = checker_check_expr_stmnt( ctx, st )
            case ^BlockStmnt:    ok = checker_check_block_stmnt( ctx, st )
            case ^ContinueStmnt: ok = checker_check_continue_stmnt( ctx, st )
            case ^BreakStmnt:    ok = checker_check_break_stmnt( ctx, st )
            case ^IfStmnt:       ok = checker_check_if_stmnt( ctx, st )
            case ^ForLoop:       ok = checker_check_for_loop( ctx, st )
            case ^WhileLoop:     ok = checker_check_while_loop( ctx, st )
            case ^InfiniteLoop:  ok = checker_check_inf_loop( ctx, st )
        }

        if !ok do return false
    }

    return true
}


checker_check_struct_decl :: proc( ctx: ^CheckerContext, d: ^StructDecl ) -> bool
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


checker_check_enum_decl :: proc( ctx: ^CheckerContext, d: ^EnumDecl ) -> bool
{
    if d.type == nil {
        ty := new_type( PrimitiveType )
        ty.kind = .USize // should this be an isize?

        d.type = ty
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


checker_check_union_decl :: proc( ctx: ^CheckerContext, d: ^UnionDecl ) -> bool
{
    log_error( "impl check_union_decl" )
    return false
}


checker_check_proc_decl :: proc( ctx: ^CheckerContext, d: ^ProcDecl ) -> bool
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
        body_ok := checker_check_scope( ctx, d.body )
        if !body_ok do return false
    }

    return true
}


checker_check_var_decl :: proc( ctx: ^CheckerContext, d: ^VarDecl ) -> bool
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
        val_ok := checker_check_expr( ctx, d.default_value )
        if !val_ok do return false

        if d.type == nil {
            d.type = d.default_value.type
        } else if !ty_are_eq( d.type, d.default_value.type ) {
            log_spanned_error( &d.span, "mismatched types! expression's type doesn't match declaration's type" )
            return false
        }
    }

    sc.symbols[d.name] = d
    return true
}


checker_check_expr_stmnt :: proc( ctx: ^CheckerContext, s: ^ExprStmnt ) -> bool
{
    log_error( "impl check_expr_stmnt" )
    return false
}


checker_check_block_stmnt :: proc( ctx: ^CheckerContext, s: ^BlockStmnt ) -> bool
{
    log_error( "impl check_block_stmnt" )
    return false
}


checker_check_continue_stmnt :: proc( ctx: ^CheckerContext, s: ^ContinueStmnt ) -> bool
{
    log_error( "impl check_continue_stmnt" )
    return false
}


checker_check_break_stmnt :: proc( ctx: ^CheckerContext, s: ^BreakStmnt ) -> bool
{
    log_error( "impl check_break_stmnt" )
    return false
}


checker_check_if_stmnt :: proc( ctx: ^CheckerContext, s: ^IfStmnt ) -> bool
{
    log_error( "impl check_if_stmnt" )
    return false
}


checker_check_for_loop :: proc( ctx: ^CheckerContext, l: ^ForLoop ) -> bool
{
    log_error( "impl check_for_loop" )
    return false
}


checker_check_while_loop :: proc( ctx: ^CheckerContext, l: ^WhileLoop ) -> bool
{
    log_error( "impl check_while_loop" )
    return false
}


checker_check_inf_loop :: proc( ctx: ^CheckerContext, l: ^InfiniteLoop ) -> bool
{
    log_error( "impl check_inf_loop" )
    return false
}


checker_check_expr :: proc( ctx: ^CheckerContext, e: ^Expr ) -> bool
{
    log_error( "impl check_expr" )
    return false
}


lookup_type :: proc( s: ^Scope, t: ^Type ) -> ^Type
{
    _ = s

    switch ty in t.derived {
        case ^EnumType, ^UnionType, ^StructType:
            // The presence of these means they've already been
            // looked up, so just return the pointer
            return t
        case ^PrimitiveType:
            // These need no lookup since they exist always, everywhere
            return t
    }

    return nil
}
