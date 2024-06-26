package main


cg_emit_stmnt :: proc( ctx: ^CheckerContext, stmnt: ^Stmnt ) -> bool
{
    switch s in stmnt.derived_stmnt {
        case ^ConstDecl:
        case ^VarDecl:
        case ^EnumVariantDecl:
        case ^UnionVariantDecl:
        case ^ExprStmnt:
        case ^ContinueStmnt:
        case ^BreakStmnt:
	    case ^ReturnStmnt:
    }

    log_error( "impl cg_emit_stmnt" )
    return false
}

cg_emit_expr :: proc( ctx: ^CheckerContext, expr: ^Expr ) -> bool
{
    switch e in expr.derived_expr {
        case ^ProcProto:
        case ^Ident:
        case ^StringLiteralExpr:
        case ^NumberLiteralExpr:
        case ^NamedStructLiteralExpr:
        case ^AnonStructLiteralExpr:
        case ^MemberAccessExpr:
        case ^ImplicitSelectorExpr:
        case ^Scope:
        case ^IfExpr:
        case ^ForLoop:
        case ^WhileLoop:
        case ^InfiniteLoop:
        case ^RangeExpr:
        case ^UnaryOpExpr:
        case ^BinOpExpr:
        case ^ProcCallExpr:
        case ^PrimitiveTypeExpr:
        case ^PointerTypeExpr:
        case ^SliceTypeExpr:
        case ^ArrayTypeExpr:
    }

    log_error( "impl cg_emit_expr" )
    return false
}
