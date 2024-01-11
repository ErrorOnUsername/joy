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
	^StructType,
	^EnumType,
	^UnionType,
	^ProcType,
	^PointerType,
	^ArrayType,
	^SliceType,
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
	decl: ^StructDecl,
}

EnumType :: struct
{
	using type: Type,
	decl: ^EnumDecl,
}

UnionType :: struct
{
	using type: Type,
	decl: ^UnionDecl,
}

ProcType :: struct
{
	using type: Type,
	decl: ^ProcDecl,
}

PointerType :: struct
{
	using type: Type,
	base_type:  ^Type,
}

ArrayType :: struct
{
	using type: Type,
	base_type:  ^Type,
}

SliceType :: struct
{
	using type: Type,
	base_type:  ^Type,
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
	UntypedInt,
	UntypedString,
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
		case .UntypedInt:
			return true
		case .UntypedString:
			return false
	}

	return false
}


primitive_kind_is_float :: proc( kind: PrimitiveKind ) -> bool
{
	switch kind {
		case .Bool:
			return false
		case .U8,  .I8,  .U16, .I16,
		     .U32, .I32, .U64, .I64,
		     .USize, .ISize:
			return false
		case .F32, .F64:
			return true
		case .String, .CString, .RawPtr, .Range:
			return false
		case .UntypedInt:
			return false
		case .UntypedString:
			return false
	}

	return false
}


ty_is_int :: proc( t: ^Type ) -> bool
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType, ^ProcType, ^PointerType, ^ArrayType, ^SliceType:
			return false
		case ^PrimitiveType:
			return primitive_kind_is_int( ty.kind )
	}

	return false
}


ty_is_float :: proc( t: ^Type ) -> bool
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType, ^ProcType, ^PointerType, ^ArrayType, ^SliceType:
			return false
		case ^PrimitiveType:
			return primitive_kind_is_float( ty.kind )
	}

	return false
}


ty_is_number :: proc( t: ^Type ) -> bool
{
	return ty_is_int( t ) || ty_is_float( t )
}


ty_is_bool :: proc( t: ^Type ) -> bool
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType, ^ProcType, ^PointerType, ^ArrayType, ^SliceType:
			return false
		case ^PrimitiveType:
			return ty.kind == .Bool
	}

	return false
}


ty_is_string :: proc( t: ^Type ) -> bool
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType, ^ProcType, ^PointerType, ^ArrayType, ^SliceType:
			return false
		case ^PrimitiveType:
			return ty.kind == .String || ty.kind == .CString
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
		case .UntypedInt, .UntypedString: return false // Does that make sense?
	}

	return false
}


ty_get_base :: proc( t: ^Type ) -> ^Type
{
	switch ty in t.derived {
		case ^StructType, ^EnumType, ^UnionType, ^PrimitiveType, ^ProcType, ^ArrayType, ^SliceType:
			return t
		case ^PointerType:
			return ty_get_base( ty.base_type )
	}

	return nil
}


ty_are_eq :: proc( l_ty: ^Type, r_ty: ^Type ) -> bool
{
	if l_ty.owning_mod != r_ty.owning_mod do return false

	switch l in l_ty.derived {
		case ^StructType:
			r, r_ok := r_ty.derived.(^StructType)
			if !r_ok do return false

			return l.decl == r.decl
		case ^EnumType:
			r, r_ok := r_ty.derived.(^EnumType)
			if !r_ok do return false

			return l.decl == r.decl
		case ^UnionType:
			r, r_ok := r_ty.derived.(^UnionType)
			if !r_ok do return false

			return l.decl == r.decl
		case ^ProcType:
			r, r_ok := r_ty.derived.(^ProcType)
			if !r_ok do return false

			return l.decl == r.decl
		case ^PrimitiveType:
			r, r_ok := r_ty.derived.(^PrimitiveType)
			if !r_ok do return false

			return l.kind == r.kind
		case ^PointerType: // TODO: impl
		case ^ArrayType:
		case ^SliceType:
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
ty_builtin_untyped_int: ^Type
ty_builtin_untyped_string: ^Type


init_default_types :: proc()
{
	ty: ^PrimitiveType

	ty = new_type( PrimitiveType, nil )
	ty.kind = .Bool
	ty_builtin_bool = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .U8
	ty_builtin_u8 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .I8
	ty_builtin_i8 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .U16
	ty_builtin_u16 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .I16
	ty_builtin_i16 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .U32
	ty_builtin_u32 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .I32
	ty_builtin_i32 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .U64
	ty_builtin_u64 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .I64
	ty_builtin_i64 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .USize
	ty_builtin_usize = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .ISize
	ty_builtin_isize = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .F32
	ty_builtin_f32 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .F64
	ty_builtin_f64 = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .String
	ty_builtin_string = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .CString
	ty_builtin_cstring = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .RawPtr
	ty_builtin_rawptr = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .Range
	ty_builtin_range = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .UntypedInt
	ty_builtin_untyped_int = ty

	ty = new_type( PrimitiveType, nil )
	ty.kind = .UntypedString
	ty_builtin_untyped_string = ty
}
