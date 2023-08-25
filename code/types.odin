package main


AnyType :: union
{
    ^StructType,
    ^EnumType,
    ^UnionType,
    ^PrimitiveType,
}

Type :: struct
{
    span: Span,
    derived: AnyType,
}

StructType :: struct
{
    using type: Type,
}

EnumType :: struct
{
    using type: Type,
}

UnionType :: struct
{
    using type: Type,
}

PrimitiveType :: struct
{
    using type: Type,
}
