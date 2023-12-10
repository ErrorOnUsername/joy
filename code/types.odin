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
	owning_mod: ^Module,
	derived: AnyType,
}

StructType :: struct
{
	using type: Type,
	name: string,
}

EnumType :: struct
{
	using type: Type,
	name: string,
}

UnionType :: struct
{
	using type: Type,
	name: string,
}


PrimitiveKind :: enum
{
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
}

type_prim_kind_from_tk :: proc( tk: TokenKind ) -> PrimitiveKind
{
	#partial switch tk {
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


primitive_kind_is_int :: proc( kind: PrimitiveKind ) -> bool
{
	switch kind {
		case .Bool:
			return false
		case .U8,  .I8,  .U16, .I16,
		     .U32, .I32, .U64, .I64,
		     .USize, .ISize:
			return true
		case .F32, .F64, .String, .CString, .RawPtr, .Range:
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
		case .Bool:  return false
		case .U8:    return i <= bits.U8_MAX
		case .I8:    return i <= bits.I8_MAX
		case .U16:   return i <= bits.U16_MAX
		case .I16:   return i <= bits.I16_MAX
		case .U32:   return i <= bits.U32_MAX
		case .I32:   return i <= bits.I32_MAX
		case .U64:   return u64( i ) <= bits.U64_MAX
		case .I64:   return i64( i ) <= bits.I64_MAX
		case .USize: return true
		case .ISize: return true
		case .F32, .F64, .String, .CString, .RawPtr, .Range: return false
	}

	return false
}


ty_are_eq :: proc( l_ty: ^Type, r_ty: ^Type ) -> bool
{
	if l_ty.owning_mod != r_ty.owning_mod do return false

	switch l in l_ty.derived {
		case ^StructType:
			r, r_ok := r_ty.derived.(^StructType)
			if !r_ok do return false

			return l.name == r.name
		case ^EnumType:
			r, r_ok := r_ty.derived.(^EnumType)
			if !r_ok do return false

			return l.name == r.name
		case ^UnionType:
			r, r_ok := r_ty.derived.(^UnionType)
			if !r_ok do return false

			return l.name == r.name
		case ^PrimitiveType:
			r, r_ok := r_ty.derived.(^PrimitiveType)
			if !r_ok do return false

			return l.kind == r.kind
	}

	return false
}


ty_builtin_bool: ^Type
ty_builtin_u8: ^Type
ty_builtin_i8: ^Type
ty_builtin_u16: ^Type
ty_builtin_i16: ^Type
ty_builtin_u32: ^Type
ty_builtin_i32: ^Type
ty_builtin_u64: ^Type
ty_builtin_i64: ^Type
ty_builtin_usize: ^Type
ty_builtin_isize: ^Type
ty_builtin_f32: ^Type
ty_builtin_f64: ^Type
ty_builtin_string: ^Type
ty_builtin_cstring: ^Type
ty_builtin_rawptr: ^Type
ty_builtin_range: ^Type


init_default_types :: proc()
{
    ty: ^PrimitiveType

    ty = new_type( PrimitiveType )
    ty.kind = .Bool
    ty_builtin_bool = ty

    ty = new_type( PrimitiveType )
    ty.kind = .U8
    ty_builtin_u8 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .I8
    ty_builtin_i8 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .U16
    ty_builtin_u16 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .I16
    ty_builtin_i16 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .U32
    ty_builtin_u32 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .I32
    ty_builtin_i32 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .U64
    ty_builtin_u64 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .I64
    ty_builtin_i64 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .USize
    ty_builtin_usize = ty

    ty = new_type( PrimitiveType )
    ty.kind = .ISize
    ty_builtin_isize = ty

    ty = new_type( PrimitiveType )
    ty.kind = .F32
    ty_builtin_f32 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .F64
    ty_builtin_f64 = ty

    ty = new_type( PrimitiveType )
    ty.kind = .String
    ty_builtin_string = ty

    ty = new_type( PrimitiveType )
    ty.kind = .CString
    ty_builtin_cstring = ty

    ty = new_type( PrimitiveType )
    ty.kind = .RawPtr
    ty_builtin_rawptr = ty

	ty = new_type( PrimitiveType )
	ty.kind = .Range
	ty_builtin_range = ty
}
