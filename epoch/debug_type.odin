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

@(private = "file")
void_type := DebugTypeVoid { }

get_void_debug_type :: proc() -> ^DebugType {
	return &void_type
}

@(private = "file")
bool_type := DebugTypeBool { }

get_bool_debug_type :: proc() -> ^DebugType {
	return &bool_type
}

@(private = "file")
int_type_table := [?]DebugTypeInt {
	{ int_bits = 8 },
	{ int_bits = 16 },
	{ int_bits = 32 },
	{ int_bits = 64 },
}

@(private = "file")
uint_type_table := [?]DebugTypeUInt {
	{ int_bits = 8 },
	{ int_bits = 16 },
	{ int_bits = 32 },
	{ int_bits = 64 },
}

get_int_debug_type :: proc(bit_count: int, is_signed: bool) -> ^DebugType {
	if is_signed {
		if bit_count <= 8 do return &int_type_table[0]
		if bit_count <= 16 do return &int_type_table[1]
		if bit_count <= 32 do return &int_type_table[2]
		if bit_count <= 64 do return &int_type_table[3]
	}
	if bit_count <= 8 do return &uint_type_table[0]
	if bit_count <= 16 do return &uint_type_table[1]
	if bit_count <= 32 do return &uint_type_table[2]
	if bit_count <= 64 do return &uint_type_table[3]

	unreachable()
}

@(private = "file")
f32_type := DebugTypeF32 { }

get_f32_debug_type :: proc() -> ^DebugType {
	return &f32_type
}

@(private = "file")
f64_type := DebugTypeF64 { }

get_f64_debug_type :: proc() -> ^DebugType {
	return &f64_type
}

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

RegisterClass :: enum {
	IntRegister, // rdi, rsi, etc...
	VectorRegister, // xmm0...
	StackSlot, // structs that can't fit / aggregate return
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

get_debug_type_register_class :: proc(dbg_ty: ^DebugType) -> RegisterClass {
	size := debug_type_get_size(dbg_ty)
	if size == 1 || size == 2 || size == 4 || size == 8 { // this is according to msft so its probably fucked on sysv
		return .VectorRegister if debug_type_is_float(dbg_ty) else .IntRegister
	}
	return .StackSlot
}

get_type_with_register_class :: proc(reg: RegisterClass, dt: ^DebugType) -> Type {
	switch reg {
		case .IntRegister:
			if debug_type_is_ptr(dt) do return TY_PTR

			sz := debug_type_get_size(dt)
			if sz == 1 do return TY_I8
			else if sz == 2 do return TY_I16
			else if sz == 4 do return TY_I32
			else if sz == 8 do return TY_I64
			unreachable()
		case .VectorRegister:
			#partial switch t in dt.extra {
				case ^DebugTypeF32: return TY_F32
				case ^DebugTypeF64: return TY_F64
			}
			unreachable()
		case .StackSlot:
			return TY_PTR
	}
	unreachable()
}

new_function_proto_from_debug_type :: proc(m: ^Module, dbg_ty: ^DebugType) -> ^FunctionProto {
	d, is_fn := dbg_ty.extra.(^DebugTypeFn)
	assert(is_fn)

	proto, _ := new(FunctionProto, m.allocator)
	proto.params = make([]FunctionParam, len(d.params), m.allocator)
	for p, i in d.params {
		reg := get_debug_type_register_class(p.field_ty)
		t := get_type_with_register_class(reg, p.field_ty)

		proto.params[i].name = p.name
		proto.params[i].type = t
	}

	proto.returns = make([]FunctionParam, len(d.returns), m.allocator)
	for r, i in d.returns {
		reg := get_debug_type_register_class(r)
		t := get_type_with_register_class(reg, r)

		proto.returns[i].name = "$ret" // FIXME(RD): These should probably have better names
		proto.returns[i].type = t
	}

	return proto
}

