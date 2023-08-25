package main

import "core:intrinsics"
import "core:mem"


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
    owning_pkg:     ^Package,
    platform_flags: PlatformFlags,
    private_scope:  ^Scope,
    imports:        [dynamic]^ImportStmnt,
}

Scope :: struct
{
    using node: Node,
    decls:      [dynamic]^Decl,
}



//
// Declarations
//

StructDecl :: struct
{
    using decl: Decl,
}

EnumDecl :: struct
{
    using decl: Decl,
}

UnionDecl :: struct
{
    using decl: Decl,
}

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

VarDecl :: struct
{
    using decl:    Decl,
    default_value: ^Expr,
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
    ^StructDecl,
    ^EnumDecl,
    ^UnionDecl,
    ^ProcDecl,
    ^ForeignLibraryDecl,
    ^VarDecl,
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
    ^Scope,
    ^Decl,
    ^Stmnt,
    ^Expr,
}

Node :: struct
{
    span:    Span,
    type:    ^Type,
    derived: AnyNode,
}


new_node :: proc( $T: typeid, span: Span ) -> ^T
{
    new_node, _     := mem.new( T )
    new_node.span    = span
    base: ^Node      = new_node
    _                = base

    when intrinsics.type_has_field( T, "derived_decl" ) {
        new_node.derived      = cast(^Decl) new_node
        new_node.derived_decl = new_node
    }

    when intrinsics.type_has_field( T, "derived_stmnt" ) {
        new_node.derived       = cast(^Stmnt) new_node
        new_node.derived_stmnt = new_node
    }

    when intrinsics.type_has_field( T, "derived_expr" ) {
        new_node.derived      = cast(^Expr) new_node
        new_node.derived_expr = new_node
    }

    return new_node
}
