package main


PlatformFlags :: bit_set[Platform]
Platform :: enum
{
    Windows,
    Darwin,
    Linux,
}

Package :: struct
{
    shared_scope: ^Scope,
    modules:      [dynamic]^Module,
}

Module :: struct
{
    platform_flags: PlatformFlags,
    private_scope:  ^Scope,
    imports:        [dynamic]^ImportStmnt,
}

Scope :: struct
{
    decls: [dynamic]^Decl,
}



//
// Declarations
//

ProcLinkage :: enum
{
    Internal,
    Foreign,
}

ProcDecl :: struct
{
    using decl:       Decl,
    linkage:          ProcLinkage,
    foreign_lib_name: ^Ident,
}

ForeignLibraryDecl :: struct
{
    using decl:        Decl,
    is_system_library: bool,
    library_path:      string,
}



//
// Statements
//

ImportStmnt :: struct
{
    using stmnt: Stmnt,
}



//
// Expressions
//

Ident :: struct
{
    using expr: Expr,
    name:       string,
}



AnyDecl :: union
{
    ^ProcDecl,
    ^ForeignLibraryDecl,
}

Decl :: struct
{
    using node:   Node,
    name:         string,
    derived_decl: AnyDecl,
}

AnyStmnt :: struct
{
    ^ImportStmnt,
}

Stmnt :: struct
{
    using node:    Node,
    derived_stmnt: AnyStmnt,
}

AnyExpr :: struct
{
    ^Ident,
}

Expr :: struct
{
    using node:   Node,
    derived_expr: AnyExpr,
}

AnyNode :: union
{
    ^Decl,
    ^Stmnt,
    ^Expr,
}

Node :: struct
{
    span:    Span,
    derived: AnyNode,
}


new_node :: proc( $T: typeid, span: Span ) -> ^T
{
    new_node, _     := mem.new( T )
    new_node.span    = span
    new_node.derived = new_node
    base: ^Node      = new_node
    _                = base

    when intrinsics.type_has_field( T, "derived_decl" ) {
        new_new.derived_decl = new_node
    }

    when intrinsics.type_has_field( T, "derived_stmnt" ) {
        new_new.derived_stmnt = new_node
    }

    when intrinsics.type_has_field( T, "derived_expr" ) {
        new_new.derived_expr = new_node
    }

    return new_node
}
