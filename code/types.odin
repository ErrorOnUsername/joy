package main

import "core:fmt"
import "core:math/bits"
import "core:mem"


new_type :: proc( $T: typeid, mod: ^Module, name: string ) -> ^T
{
	new_type, _ := mem.new( T )
	new_type.derived    = new_type
	new_type.owning_mod = mod

	new_type.name = name

	return new_type
}


AnyType :: union
{
	^PointerType,
	^SliceType,
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
	name: string,
	size: int,
	alignment: int,
}

PointerType :: struct
{
	using type: Type,
	underlying: ^Type,
}

SliceType :: struct
{
	using type: Type,
	underlying: ^Type,
}

StructType :: struct
{
	using type: Type,
	ast_scope: ^Scope,
	members: [dynamic]^Type,
}

EnumType :: struct
{
	using type: Type,
	ast_scope: ^Scope,
	underlying: ^Type,
}

UnionType :: struct
{
	using type: Type,
	ast_scope: ^Scope,
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


ty_builtin_untyped_int: ^Type
ty_builtin_untyped_string: ^Type

ty_builtin_void: ^Type
ty_builtin_bool: ^Type
ty_builtin_usize: ^Type
ty_builtin_isize: ^Type
ty_builtin_u8: ^Type
ty_builtin_i8: ^Type
ty_builtin_u16: ^Type
ty_builtin_i16: ^Type
ty_builtin_u32: ^Type
ty_builtin_i32: ^Type
ty_builtin_u64: ^Type
ty_builtin_i64: ^Type
ty_builtin_f32: ^Type
ty_builtin_f64: ^Type
ty_builtin_string: ^Type
ty_builtin_cstring: ^Type
ty_builtin_range: ^Type
ty_builtin_rawptr: ^Type

new_primitive_type :: proc( kind: PrimitiveKind, name: string, size: int, align: int ) -> ^Type
{
	ty := new_type( PrimitiveType, nil, name )
	ty.kind = kind
	ty.size = size
	ty.alignment = align
	return ty
}

init_builtin_types :: proc(target: TargetDesc)
{
	word_size := target_get_word_size(target)

	ty_builtin_untyped_int = new_primitive_type( .UntypedInt, "untyped int", -1, -1 )
	ty_builtin_untyped_string = new_primitive_type( .UntypedString, "untyped string", -1, -1 )
	ty_builtin_void = new_primitive_type( .Void, "void", 0, 0 )
	ty_builtin_bool = new_primitive_type( .Bool, "bool", 1, 1 )
	ty_builtin_usize = new_primitive_type( .USize, "uint", word_size, word_size)
	ty_builtin_isize = new_primitive_type( .ISize, "int", word_size, word_size)
	ty_builtin_u8 = new_primitive_type( .U8, "u8", 1, 1 )
	ty_builtin_i8 = new_primitive_type( .I8, "i8", 1, 1 )
	ty_builtin_u16 = new_primitive_type( .U16, "u16", 2, 2 )
	ty_builtin_i16 = new_primitive_type( .I16, "i16", 2, 2 )
	ty_builtin_u32 = new_primitive_type( .U32, "u32", 4, 4 )
	ty_builtin_i32 = new_primitive_type( .I32, "i32", 4, 4 )
	ty_builtin_u64 = new_primitive_type( .U64, "u64", 8, 8 )
	ty_builtin_i64 = new_primitive_type( .I64, "i64", 8, 8 )
	ty_builtin_f32 = new_primitive_type( .F32, "f32", 4, 4 )
	ty_builtin_f64 = new_primitive_type( .F64, "f64", 8, 8 )
	ty_builtin_string = new_primitive_type( .String, "string", 2 * word_size, word_size)
	ty_builtin_cstring = new_primitive_type( .CString, "cstring", word_size, word_size)
	ty_builtin_range = new_primitive_type( .Range, "range", 2 * word_size, word_size)
	ty_builtin_rawptr = new_primitive_type( .RawPtr, "rawptr", word_size, word_size)
}

ty_is_untyped_builtin :: proc( ty: ^Type ) -> bool
{
	return ty == ty_builtin_untyped_string ||
	       ty == ty_builtin_untyped_int
}

ty_is_void :: proc( ty: ^Type ) -> bool
{
	return ty == ty_builtin_void
}

ty_is_bool :: proc( ty: ^Type ) -> bool
{
	return ty == ty_builtin_bool
}

ty_is_prim :: proc( ty: ^Type, kind: PrimitiveKind ) -> bool
{
	switch t in ty.derived {
		case ^PrimitiveType:
			return t.kind == kind
		case ^PointerType, ^SliceType, ^StructType,
		     ^EnumType, ^UnionType, ^FnType:
			return false
	}

	return false
}

ty_is_number :: proc( ty: ^Type ) -> bool
{
	switch t in ty.derived {
		case ^PrimitiveType:
			#partial switch t.kind {
				case .U8, .I8, .U16, .I16, .U32,
				     .I32, .U64, .I64, .USize,
				     .ISize, .F32, .F64:
					return true
			}
		case ^PointerType, ^SliceType, ^StructType,
		     ^EnumType, ^UnionType, ^FnType:
			return false
	}

	return false
}

ty_is_integer :: proc( ty: ^Type ) -> bool
{
	switch t in ty.derived {
		case ^PrimitiveType:
			#partial switch t.kind {
				case .U8, .I8, .U16, .I16, .U32,
				     .I32, .U64, .I64, .USize,
				     .ISize:
					return true
			}
		case ^PointerType, ^SliceType, ^StructType,
		     ^EnumType, ^UnionType, ^FnType:
			return false
	}

	return false
}

ty_is_range :: proc( ty: ^Type ) -> bool
{
	return ty == ty_builtin_range
}

ty_is_array_or_slice :: proc( ty: ^Type ) -> bool
{
	switch t in ty.derived {
		case ^SliceType:
			return true
		case ^PointerType, ^PrimitiveType, ^StructType,
		     ^EnumType, ^UnionType, ^FnType:
			return false
	}

	return false
}

ty_is_pointer :: proc( ty: ^Type ) -> bool
{
	#partial switch t in ty.derived {
		case ^PointerType:
			return true
	}

	return false
}

ty_is_struct :: proc( ty: ^Type ) -> bool
{
	#partial switch t in ty.derived {
		case ^StructType:
			return true
	}

	return false
}

ty_is_union :: proc( ty: ^Type ) -> bool
{
	#partial switch t in ty.derived {
		case ^UnionType:
			return true
	}

	return false
}

ty_is_enum :: proc( ty: ^Type ) -> bool
{
	#partial switch t in ty.derived {
		case ^EnumType:
			return true
	}

	return false
}

ty_get_array_underlying :: proc( ty: ^Type ) -> ^Type
{

	#partial switch t in ty.derived {
		case ^SliceType:
			return t.underlying
		case:
			assert( false, "type is not an array or slice" )
	}

	return nil
}
