package main

import "core:fmt"
import "core:mem"


new_type :: proc( $T: typeid ) -> ^T
{
	new_type, _ := mem.new( T )
	new_type.derived = new_type

	return new_type
}


AnyType :: union
{
	^StructType,
	^EnumType,
	^UnionType,
	^PrimitiveType,
}

Type :: struct
{
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


PrimitiveKind :: enum
{
	U8,
	I8,
	U16,
	I16,
	U32,
	I32,
	U64,
	I64,
	USize,
	ISize,
	F32,
	F64,
	String,
	CString,
	RawPtr,
}

type_prim_kind_from_tk :: proc( tk: TokenKind ) -> PrimitiveKind
{
	#partial switch tk {
		case .U8:
			return .U8
		case .I8:
			return .I8
		case .U16:
			return .U16
		case .I16:
			return .I16
		case .U32:
			return .U32
		case .I32:
			return .I32
		case .U64:
			return .U64
		case .I64:
			return .I64
		case .USize:
			return .USize
		case .ISize:
			return .ISize
		case .F32:
			return .F32
		case .F64:
			return .F64
		case .String:
			return .String
		case .CString:
			return .CString
		case .RawPtr:
			return .RawPtr
	}

	fmt.panicf( "Unknown primitive: {}", tk )
}

PrimitiveType :: struct
{
	using type: Type,
	kind:       PrimitiveKind,
}
