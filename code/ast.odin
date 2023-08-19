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

AnyDecl :: union
{
    ^ProcDecl,
    ^ForeignLibraryDecl,
}

Decl :: struct
{
    using node: Node,
    derived:    AnyDecl,
}

ProcLinkage :: enum
{
    Internal,
    Foreign,
}

ProcDecl :: struct
{
    linkage:          ProcLinkage,
    foreign_lib_name: ^Ident,
}

ForeignLibraryDecl :: struct
{
    is_system_library: bool,
    library_path:      string,
}

ImportStmnt :: struct
{
}

Ident :: struct
{
}

Node :: struct
{
    span: Span,
}

