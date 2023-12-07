package main


checker_initialize_symbol_tables :: proc( pkgs: []^Package ) -> bool
{
    for pkg in pkgs {
        for mod in pkg.modules {
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
