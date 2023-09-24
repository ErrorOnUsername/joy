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
    stmnts:      [dynamic]^Stmnt,
    parent:     ^Scope,
}



//
// Declarations
//

StructDecl :: struct
{
    using stmnt: Stmnt,
    name:        string,
    members:     [dynamic]^VarDecl,
}

EnumVariant :: struct
{
    using node: Node,
    name:       string,
}

EnumDecl :: struct
{
    using stmnt: Stmnt,
    name:        string,
    variants:    [dynamic]^EnumVariant,
}

UnionDecl :: struct
{
    using stmnt: Stmnt,
    name:        string,
}

ProcLinkage :: enum
{
    Internal,
    Foreign,
}

ProcDecl :: struct
{
    using stmnt:      Stmnt,
    name:             string,
    linkage:          ProcLinkage,
    foreign_lib_name: ^Ident,
    params:           [dynamic]^VarDecl,
    body:             ^Scope,
}

VarDecl :: struct
{
    using stmnt:   Stmnt,
    name:          string,
    default_value: ^Expr,
}

ForeignLibraryDecl :: struct
{
    using stmnt:       Stmnt,
    name:              string,
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

ExprStmnt :: struct
{
    using stmnt: Stmnt,
    expr:        ^Expr,
}



//
// Expressions
//

Ident :: struct
{
    using expr: Expr,
    name:       string,
}


AnyStmnt :: union 
{
    ^ImportStmnt,
    ^StructDecl,
    ^EnumDecl,
    ^UnionDecl,
    ^ProcDecl,
    ^ForeignLibraryDecl,
    ^VarDecl,
    ^ExprStmnt,
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
    ^Stmnt,
    ^Expr,
    ^EnumVariant,
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
