package epoch

DebugType :: struct {
	extra: DebugTypeExtra,
}

DebugTypeExtra :: union {
	^DebugTypeVoid,
	^DebugTypeBool,
	^DebugTypeInt,
	^DebugTypeUInt,
	^DebugTypeF32,
	^DebugTypeF64,
	^DebugTypeStruct,
	^DebugTypeField,
	^DebugTypeUnion,
	^DebugTypePointer,
	^DebugTypeArray,
	^DebugTypeFn,
}

DebugTypeBool :: struct {
	using type: DebugType,
}

DebugTypeVoid :: struct {
	using type: DebugType,
}

DebugTypeInt :: struct {
	using type: DebugType,
	int_bits: int,
}

DebugTypeUInt :: struct {
	using type: DebugType,
	int_bits: int,
}

DebugTypeF32 :: struct {
	using type: DebugType,
}

DebugTypeF64 :: struct {
	using type: DebugType,
}

DebugTypeStruct :: struct {
	using type: DebugType,
	size: int,
	align: int,
	name: string,
	fields: []^DebugTypeField,
}

DebugTypeField :: struct {
	using type: DebugType,
	name: string,
	field_ty: ^DebugType,
	offset: int,
}

DebugTypeUnion :: struct {
	using type: DebugType,
	size: int,
	align: int,
	name: string,
	variants: []^DebugTypeStruct,
}

DebugTypePointer :: struct {
	using type: DebugType,
	underlying: ^DebugType,
}

DebugTypeArray :: struct {
	using type: DebugType,
	elem_type: ^DebugType,
	count: uint,
}

DebugTypeFn :: struct {
	using type: DebugType,
	name: string,
	params: []^DebugTypeField,
	returns: []^DebugType,
}

dbg_ty_void: ^DebugType
dbg_ty_bool: ^DebugType
dbg_ty_int8: ^DebugType
dbg_ty_int16: ^DebugType
dbg_ty_int32: ^DebugType
dbg_ty_int64: ^DebugType
dbg_ty_uint8: ^DebugType
dbg_ty_uint16: ^DebugType
dbg_ty_uint32: ^DebugType
dbg_ty_uint64: ^DebugType

get_int_debug_type :: proc(bit_count: int, is_signed: bool) -> ^DebugType {
	if is_signed {
		if bit_count <= 8 do return dbg_ty_int8
		if bit_count <= 16 do return dbg_ty_int16
		if bit_count <= 32 do return dbg_ty_int32
		if bit_count <= 64 do return dbg_ty_int64
	}
	if bit_count <= 8 do return dbg_ty_uint8
	if bit_count <= 16 do return dbg_ty_uint16
	if bit_count <= 32 do return dbg_ty_uint32
	if bit_count <= 64 do return dbg_ty_uint64

	unreachable()
}
f32_type := DebugType { DebugTypeF32 { } }
f64_type := DebugType { DebugTypeF64 { } }

@(private = "file")
new_debug_type :: proc($T: typeid, mod: ^Module) -> ^T {
	t, _ := new(T, mod.allocator)
	t.extra = t
	return t
}

new_debug_type_struct :: proc(mod: ^Module, name: string, field_count: int, size: int, align: int) -> ^DebugTypeStruct {
	s := new_debug_type(DebugTypeStruct, mod)
	s.size = size
	s.align = align
	s.name = name
	s.fields = make([]^DebugTypeField, field_count, mod.allocator)
	return s
}

new_debug_type_field :: proc(mod: ^Module, name: string, ty: ^DebugType, offset: int) -> ^DebugTypeField {
	f := new_debug_type(DebugTypeField, mod)
	f.name = name
	f.field_ty = ty
	f.offset = offset
	return f
}

new_debug_type_union :: proc(mod: ^Module, name: string, variant_count: int, size: int, align: int) -> ^DebugTypeUnion {
	u := new_debug_type(DebugTypeUnion, mod)
	u.size = size
	u.align = align
	u.name = name
	u.variants = make([]^DebugTypeStruct, variant_count, mod.allocator)
	return u
}

new_debug_type_ptr :: proc(mod: ^Module, underlying: ^DebugType) -> ^DebugTypePointer {
	p := new_debug_type(DebugTypePointer, mod)
	p.underlying = underlying
	return p
}

new_debug_type_array :: proc(mod: ^Module, underlying: ^DebugType, count: uint) -> ^DebugTypeArray {
	a := new_debug_type(DebugTypeArray, mod)
	a.elem_type = underlying
	a.count = count
	return a
}

new_debug_type_fn :: proc(mod: ^Module, name: string, param_count: int, return_count: int) -> ^DebugTypeFn {
	f := new_debug_type(DebugTypeFn, mod)
	f.name = name
	f.params = make([]^DebugTypeField, param_count, mod.allocator)
	f.returns = make([]^DebugType, return_count, mod.allocator)
	return f
}

debug_type_is_float :: proc(dbg_ty: ^DebugType) -> bool {
	#partial switch d in dbg_ty.extra {
		case ^DebugTypeF32, ^DebugTypeF64:
			return true
	}
	return false
}

debug_type_is_ptr :: proc(dbg_ty: ^DebugType) -> bool {
	#partial switch d in dbg_ty.extra {
		case ^DebugTypePointer:
			return true
	}
	return false
}

debug_type_get_size :: proc(dbg_ty: ^DebugType) -> int {
	switch d in dbg_ty.extra {
		case ^DebugTypeVoid:
			return 0
		case ^DebugTypeBool:
			return 1
		case ^DebugTypeInt:
			return d.int_bits / 8
		case ^DebugTypeUInt:
			return d.int_bits / 8
		case ^DebugTypeF32:
			return 4
		case ^DebugTypeF64:
			return 8
		case ^DebugTypeStruct:
			return d.size
		case ^DebugTypeField:
			unreachable()
		case ^DebugTypeUnion:
			return d.size
		case ^DebugTypePointer:
			return 8 // this is a problem if we want to run on 32-bit archs
		case ^DebugTypeArray:
			return 8
		case ^DebugTypeFn:
			return 8
	}
	unreachable()
}

