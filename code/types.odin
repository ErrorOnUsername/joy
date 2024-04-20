package main

import "core:fmt"
import "core:math/bits"
import "core:mem"


new_type :: proc( $T: typeid, mod: ^Module ) -> ^T
{
	new_type, _ := mem.new( T )
	new_type.derived    = new_type
	new_type.owning_mod = mod

	return new_type
}


AnyType :: union
{
	^PrimitiveType,
	^StructType,
	^EnumType,
	^UnionType,
	^FnType,
}

Type :: struct
{
	owning_mod: ^Module,
	derived: AnyType,
	size: u64,
	alignment: u64,
}

StructType :: struct
{
	using type: Type,
	members: [dynamic]^Type,
}

EnumType :: struct
{
	using type: Type,
	underlying: ^Type,
}

UnionType :: struct
{
	using type: Type,
	variants: [dynamic]^StructType,
}

FnType :: struct
{
	using type: Type,
	params: [dynamic]^Type,
	return_type: ^Type,
}

PrimitiveKind :: enum
{
	Void,
	Bool,
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
	Range,
	UntypedInt,
	UntypedString,
}

type_prim_kind_from_tk :: proc( tk: TokenKind ) -> PrimitiveKind
{
	#partial switch tk {
		case .Void:
			return .Void
		case .Bool:
			return .Bool
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
		case .Range:
			return .Range
	}

	fmt.panicf( "Unknown primitive: {}", tk )
}

PrimitiveType :: struct
{
	using type: Type,
	kind:       PrimitiveKind,
}


ty_builtin_void: ^Type
ty_builtin_untyped_string: ^Type

ty_is_void :: proc( ty: ^Type ) -> bool
{
	return ty == ty_builtin_void
}
