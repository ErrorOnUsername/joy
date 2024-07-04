package epoch

TypeKind :: enum {
	Int,
	Float,
	Ptr,
	Memory,
	Tuple,
	Control,
}

Type :: struct {
	kind: TypeKind,
	bitwidth: u8,
}

TY_VOID :: Type { .Int, 0 }
TY_BOOL :: Type { .Int, 1 }
TY_I8 :: Type { .Int, 8 }
TY_I16 :: Type { .Int, 16 }
TY_I32 :: Type { .Int, 32 }
TY_I64 :: Type { .Int, 64 }
TY_F32 :: Type { .Float, 32 }
TY_F64 :: Type { .Float, 64 }
TY_PTR :: Type { .Ptr, 0 }
TY_MEM :: Type { .Memory, 0 }
TY_TUPLE :: Type { .Tuple, 0 }
TY_CTRL :: Type { .Control, 0 }

ty_is_void :: proc(t: Type) -> bool {
	return t.kind == .Int && t.bitwidth == 0
}

ty_is_bool :: proc(t: Type) -> bool {
	return t.kind == .Int && t.bitwidth == 1
}

ty_is_int :: proc(t: Type) -> bool {
	return t.kind == .Int
}

ty_is_float :: proc(t: Type) -> bool {
	return t.kind == .Float
}

ty_is_ptr :: proc(t: Type) -> bool {
	return t.kind == .Ptr
}

ty_is_mem :: proc(t: Type) -> bool {
	return t.kind == .Memory
}

ty_is_tuple :: proc(t: Type) -> bool {
	return t.kind == .Tuple
}

ty_is_ctrl :: proc(t: Type) -> bool {
	return t.kind == .Control
}

