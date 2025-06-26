package main

import "../epoch"

import "core:fmt"
import "core:math/bits"
import "core:mem"
import "core:sync"


new_type :: proc($T: typeid, mod: ^Module, name: string) -> ^T {
	new_type, _ := mem.new( T )
	new_type.derived    = new_type
	new_type.owning_mod = mod

	new_type.name = name

	return new_type
}


AnyType :: union {
	^PointerType,
	^ArrayType,
	^SliceType,
	^PrimitiveType,
	^StructType,
	^EnumType,
	^UnionType,
	^FnType,
}

Type :: struct {
	owning_mod: ^Module,
	derived:    AnyType,
	name:       string,
	size:       int,
	alignment:  int,

	debug_type_mtx: sync.Recursive_Mutex, // This needs to be recursive so we don't deadlock due to self-referential type definitions (linked lists for example)
	debug_type:     ^epoch.DebugType,
}

PointerType :: struct {
	using type: Type,
	mutable:    bool,
	underlying: ^Type,
}

ArrayType :: struct {
	using type: Type,
	underlying: ^Type,
	count:      uint,
}

SliceType :: struct {
	using type: Type,
	underlying: ^Type,
}

StructMember :: struct {
	name:   string,
	ty:     ^Type,
	offset: int,
}

StructType :: struct {
	using type: Type,
	ast_scope:  ^Scope,
	members:    [dynamic]StructMember,
}

EnumVariant :: struct {
	name:  string,
	value: u64,
}

EnumType :: struct {
	using type: Type,
	ast_scope:  ^Scope,
	underlying: ^Type,
	variants:   [dynamic]EnumVariant,
}

UnionType :: struct {
	using type: Type,
	ast_scope:  ^Scope,
	variants:   [dynamic]^StructType,
}

FnParameter :: struct {
	name: string,
	ty:   ^Type,
}

FnType :: struct {
	using type:  Type,
	params:      [dynamic]FnParameter,
	return_type: ^Type,
}

PrimitiveKind :: enum {
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
	UntypedFloat,
	UntypedString,
	TypeID,
}

type_prim_kind_from_tk :: proc(tk: TokenKind) -> PrimitiveKind {
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

	fmt.panicf("Unknown primitive: {}", tk)
}

PrimitiveType :: struct {
	using type: Type,
	kind:       PrimitiveKind,
}


ty_builtin_typeid: ^Type

ty_builtin_untyped_int: ^Type
ty_builtin_untyped_float: ^Type
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

new_primitive_type :: proc(kind: PrimitiveKind, name: string, size: int, align: int) -> ^Type {
	ty := new_type(PrimitiveType, nil, name)
	ty.kind = kind
	ty.size = size
	ty.alignment = align
	return ty
}

init_builtin_types :: proc(target: TargetDesc) {
	word_size := target_get_word_size(target)

	ty_builtin_typeid = new_primitive_type(.TypeID, "type", -1, -1)
	ty_builtin_untyped_int = new_primitive_type(.UntypedInt, "untyped int", -1, -1)
	ty_builtin_untyped_float = new_primitive_type(.UntypedFloat, "untyped float", -1, -1)
	ty_builtin_untyped_string = new_primitive_type(.UntypedString, "untyped string", -1, -1)
	ty_builtin_void = new_primitive_type(.Void, "void", 0, 0)
	ty_builtin_bool = new_primitive_type(.Bool, "bool", 1, 1)
	ty_builtin_usize = new_primitive_type(.USize, "uint", word_size, word_size)
	ty_builtin_isize = new_primitive_type(.ISize, "int", word_size, word_size)
	ty_builtin_u8 = new_primitive_type(.U8, "u8", 1, 1)
	ty_builtin_i8 = new_primitive_type(.I8, "i8", 1, 1)
	ty_builtin_u16 = new_primitive_type(.U16, "u16", 2, 2)
	ty_builtin_i16 = new_primitive_type(.I16, "i16", 2, 2)
	ty_builtin_u32 = new_primitive_type(.U32, "u32", 4, 4)
	ty_builtin_i32 = new_primitive_type(.I32, "i32", 4, 4)
	ty_builtin_u64 = new_primitive_type(.U64, "u64", 8, 8)
	ty_builtin_i64 = new_primitive_type(.I64, "i64", 8, 8)
	ty_builtin_f32 = new_primitive_type(.F32, "f32", 4, 4)
	ty_builtin_f64 = new_primitive_type(.F64, "f64", 8, 8)
	ty_builtin_string = new_primitive_type(.String, "string", 2 * word_size, word_size)
	ty_builtin_cstring = new_primitive_type(.CString, "cstring", word_size, word_size)
	ty_builtin_range = new_primitive_type(.Range, "range", 2 * word_size, word_size)
	ty_builtin_rawptr = new_primitive_type(.RawPtr, "rawptr", word_size, word_size)
}

ty_eq :: proc(l_ty: ^Type, r_ty: ^Type) -> bool {
	switch l in l_ty.derived {
		case ^PointerType:
			r, is_ptr := r_ty.derived.(^PointerType)
			return is_ptr && (l.mutable == r.mutable) && ty_eq(l.underlying, r.underlying)
		case ^ArrayType:
			r, is_arr := r_ty.derived.(^ArrayType)
			return is_arr && ty_eq(l.underlying, r.underlying)
		case ^SliceType:
			r, is_slice := r_ty.derived.(^SliceType)
			return is_slice && ty_eq(l.underlying, r.underlying)
		case ^PrimitiveType:
			return l_ty == r_ty
		case ^StructType, ^EnumType, ^UnionType:
			return l_ty == r_ty // These are made unique due to the fact they're genereated when the struct is checked
		case ^FnType:
			r := r_ty.derived.(^FnType) or_return

			if len(l.params) != len(r.params) {
				return false
			}

			if !ty_eq(l.return_type, r.return_type) {
				return false
			}

			for lp, i in &l.params {
				rp := &r.params[i]
				if !ty_eq(lp.ty, rp.ty) {
					return false
				}
			}

			return true
	}

	return false
}

ty_is_typeid :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_typeid
}

ty_is_untyped_builtin :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_untyped_string ||
	       ty == ty_builtin_untyped_int ||
	       ty == ty_builtin_untyped_float
}

ty_is_void :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_void
}

ty_is_bool :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_bool
}

ty_is_prim :: proc(ty: ^Type, kind: PrimitiveKind) -> bool {
	#partial switch t in ty.derived {
		case ^PrimitiveType:
			return t.kind == kind
	}

	return false
}

ty_is_number :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^PrimitiveType:
			#partial switch t.kind {
				case .U8, .I8, .U16, .I16, .U32,
				     .I32, .U64, .I64, .USize,
				     .ISize, .F32, .F64:
					return true
			}
	}

	return false
}

ty_is_integer :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^PrimitiveType:
			#partial switch t.kind {
				case .U8, .I8, .U16, .I16, .U32,
				     .I32, .U64, .I64, .USize,
				     .ISize:
					return true
			}
	}

	return false
}

ty_is_signed_integer :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^PrimitiveType:
			#partial switch t.kind {
				case .I8, .I16, .I32, .I64, .ISize:
					return true
			}
	}

	return false
}

ty_is_range :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_range
}

ty_is_string :: proc(ty: ^Type) -> bool {
	return ty == ty_builtin_string
}

ty_is_array :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^ArrayType: return true
	}
	return false
}

ty_is_slice :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^SliceType:
			return true
	}

	return false
}

ty_is_array_or_slice :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^SliceType: return true
	}

	return false
}

ty_is_pointer :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^PointerType:
			return true
	}

	return false
}

ty_is_struct :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^StructType:
			return true
	}

	return false
}

ty_is_union :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^UnionType:
			return true
	}

	return false
}

ty_is_enum :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^EnumType:
			return true
	}

	return false
}

ty_get_array_underlying :: proc(ty: ^Type) -> ^Type {
	assert(ty_is_array_or_slice(ty))
	#partial switch t in ty.derived {
		case ^ArrayType:
			return t.underlying
		case ^SliceType:
			return t.underlying
	}

	return nil
}

ty_get_base :: proc(ty: ^Type) -> ^Type {
	t := ty

	loop: for t != nil {
		#partial switch td in t.derived {
			case ^PointerType:
				t = td.underlying
			case:
				break loop
		}
	}

	return t
}

ty_get_member :: proc(ty: ^Type, member_name: string) -> ^Type {
	#partial switch t in ty.derived {
		case ^StructType:
			for m in &t.members {
				if m.name == member_name {
					return m.ty
				}
			}
			return nil
		case ^EnumType:
			if !(member_name in t.ast_scope.symbols) {
				return nil
			}
			return t
		case ^UnionType:
			for v in &t.variants {
				if v.name == member_name {
					return v
				}
			}
			return nil
	}
	return nil
}

ty_is_mut_pointer :: proc(ty: ^Type) -> bool {
	#partial switch t in ty.derived {
		case ^PointerType:
			return t.mutable
	}
	return false
}

