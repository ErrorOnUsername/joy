package main


CheckerContext :: struct
{
    current_scope: ^Scope,
    current_proc:  ^ProcDecl,
    current_loop:  ^Stmnt,
    current_stmnt: int,
}


pump_check_package :: proc( file_id: FileID ) -> PumpResult
{
    file_data := fm_get_data( file_id )

    if !file_data.is_dir {
        log_errorf( "Package '{}' is not a directory", file_data.rel_path )
        return .Error
    }

    if file_data.pkg == nil {
        log_errorf( "Tried to typecheck a package '{}' that has not been parsed", file_data.rel_path )
        return .Error
    }

    pkg := file_data.pkg

    ctx: CheckerContext

    for mod in &pkg.modules {
        compiler_enqueue_work( .TypecheckModule, mod.file_id )
    }

    return .Continue
}


pump_check_module :: proc( file_id: FileID ) -> PumpResult
{
	file_data := fm_get_data( file_id )

	if file_data.is_dir {
		log_errorf( "Module '{}' is not a file", file_data.rel_path )
		return .Error
	}

	mod := file_data.mod
	if mod == nil {
		log_errorf( "Tried to typecheck a module '{}' that has not been parsed yet", file_data.rel_path )
	}

	ctx: CheckerContext

	scope_ok := check_scope( mod.file_scope, &ctx )
	if !scope_ok do return .Error

    return .Continue
}


check_scope :: proc( scope: ^Scope, ctx: ^CheckerContext ) -> bool
{
    ctx.current_scope = scope

    for i := 0; i < len( scope.stmnts ); i += 1 {
        ctx.current_stmnt = i

        if !check_stmnt( scope.stmnts[i], ctx ) {
            return false
        }
    }

    return true
}

check_stmnt :: proc( stmnt: ^Stmnt, ctx: ^CheckerContext ) -> bool
{
    switch s in stmnt.derived_stmnt {
	    case ^ImportStmnt:
            log_error( "impl imports" )
            return false
	    case ^StructDecl:
            if !check_struct_decl( s, ctx ) do return false
	    case ^EnumDecl:
            if !check_enum_decl( s, ctx ) do return false
	    case ^UnionDecl:
            if !check_union_decl( s, ctx ) do return false
	    case ^ProcDecl:
            if !check_proc_decl( s, ctx ) do return false
	    case ^ForeignLibraryDecl:
            log_error( "impl foreign libraries" )
            return false
	    case ^VarDecl:
            if !check_var_decl( s, ctx ) do return false
	    case ^ExprStmnt:
            if !check_expr( s.expr, ctx ) do return false
	    case ^BlockStmnt:
            if !check_scope( s.scope, ctx ) do return false
	    case ^ContinueStmnt:
            if !check_continue_stmnt( s, ctx ) do return false
	    case ^BreakStmnt:
            if !check_break_stmnt( s, ctx ) do return false
	    case ^IfStmnt:
            if !check_if_stmnt( s, ctx ) do return false
	    case ^ForLoop:
            if !check_for_loop( s, ctx ) do return false
	    case ^WhileLoop:
            if !check_while_loop( s, ctx ) do return false
	    case ^InfiniteLoop:
            if !check_inf_loop( s, ctx ) do return false
    }

    return true
}

check_struct_decl :: proc( decl: ^StructDecl, ctx: ^CheckerContext ) -> bool {
    log_error( "impl check_struct_decl" )
    return false
}

check_enum_decl :: proc( decl: ^EnumDecl, ctx: ^CheckerContext ) -> bool {
    log_error( "impl check_enum_decl" )
    return false
}

check_union_decl :: proc( decl: ^UnionDecl, ctx: ^CheckerContext ) -> bool {
    log_error( "impl check_union_decl" )
    return false
}

check_proc_decl :: proc( decl: ^ProcDecl, ctx: ^CheckerContext ) -> bool {
    log_error( "impl check_proc_decl" )
    return false
}

check_var_decl :: proc( decl: ^VarDecl, ctx: ^CheckerContext ) -> bool {
    log_error( "impl check_var_decl" )
    return false
}

check_expr :: proc( expr: ^Expr, ctx: ^CheckerContext) -> bool {
    log_error( "impl check_expr" )
    return false
}

check_continue_stmnt :: proc( stmnt: ^ContinueStmnt, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_continue_stmnt" )
	return false
}

check_break_stmnt :: proc( stmnt: ^BreakStmnt, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_continue_stmnt" )
	return false
}

check_if_stmnt :: proc( stmnt: ^IfStmnt, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_continue_stmnt" )
	return false
}

check_for_loop :: proc( loop: ^ForLoop, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_for_loop" )
	return false
}

check_while_loop :: proc( loop: ^WhileLoop, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_while_loop" )
	return false
}

check_inf_loop :: proc( loop: ^InfiniteLoop, ctx: ^CheckerContext ) -> bool {
	log_error( "impl check_inf_loop" )
	return false
}
