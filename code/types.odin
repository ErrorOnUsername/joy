package main

import "core:fmt"
import "core:math/bits"
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


primitive_kind_is_int :: proc( kind: PrimitiveKind ) -> bool
{
	switch kind {
		case .U8,  .I8,  .U16, .I16,
		     .U32, .I32, .U64, .I64,
		     .USize, .ISize:
			return true
		case .F32, .F64, .String, .CString, .RawPtr:
			return false
	}

	return false
}


ty_is_int :: proc( t: ^Type ) -> bool
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType:
			return false
		case ^PrimitiveType:
			return primitive_kind_is_int( ty.kind )
	}

	return false
}


ty_does_int_fit_in_type :: proc( t: ^PrimitiveType, i: int ) -> bool
{
	assert( primitive_kind_is_int( t.kind ) )

	switch t.kind {
		case .U8: return i <= bits.U8_MAX
		case .I8: return i <= bits.I8_MAX
		case .U16: return i <= bits.U16_MAX
		case .I16: return i <= bits.I16_MAX
		case .U32: return i <= bits.U32_MAX
		case .I32: return i <= bits.I32_MAX
		case .U64: return u64( i ) <= bits.U64_MAX
		case .I64: return i64( i ) <= bits.I64_MAX
		case .USize: return true
		case .ISize: return true
		case .F32, .F64, .String, .CString, .RawPtr: return false
	}

	return false
}
