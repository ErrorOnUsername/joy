package epoch

import "core:mem"
import "core:sync"


FunctionParam :: struct {
	debug_type: ^DebugType,
	type: Type,
	name: string,
}

FunctionProto :: struct {
	params: []FunctionParam,
	returns: []FunctionParam,
}

Linkage :: enum {
	Public,
	Private,
}

FunctionMetaState :: struct {
	entry_ctrl: ^Node,

	curr_ctrl: ^Node,
	curr_mem: ^Node,
}

Function :: struct {
	using symbol: Symbol,
	pool: mem.Dynamic_Pool,
	allocator: mem.Allocator,
	node_count: int,
	proto: ^FunctionProto,
	params: []^Node,
	start: ^Node,
	end: ^Node,
	meta: FunctionMetaState,
}

GlobalData :: []u8

Global :: struct {
	using symbol: Symbol,
	data: GlobalData,
}

Symbol :: struct {
	name: string,
	linkage: Linkage,
	derived: AnySymbol,
}

AnySymbol :: union {
	^Function,
	^Global,
}

new_symbol :: proc(m: ^Module, $T: typeid, name: string, linkage: Linkage) -> ^T {
	sync.lock(&m.allocator_lock)
	defer sync.unlock(&m.allocator_lock)

	sym, _ := new(T, m.allocator)
	sym.derived = sym
	sym.name = name
	sym.linkage = linkage

	append(&m.symbols, sym)

	return sym
}


new_global :: proc(m: ^Module, name: string, linkage: Linkage) -> ^Global {
	g := new_symbol(m, Global, name, linkage)
	return g
}


global_set_data :: proc(m: ^Module, g: ^Global, data: []u8) {
	sync.lock(&m.allocator_lock)
	defer sync.unlock(&m.allocator_lock)

	new_data, _ := make([]u8, len(data), m.allocator)
	copy(new_data, data)

	g.data = new_data
}


new_function :: proc(m: ^Module, name: string, proto: ^FunctionProto) -> ^Function {
	fn := new_symbol(m, Function, name, .Private) // TODO: hook this into the ast so that it obeys the syntax
	mem.dynamic_pool_init(&fn.pool)
	fn.allocator = mem.dynamic_pool_allocator(&fn.pool)

	fn.start = new_node(fn, .Start, TY_TUPLE, 0)
	fn.end = new_node(fn, .End, TY_CTRL, 1)

	fn.proto = proto

	fn.params = make([]^Node, len(proto.params) + 2, fn.allocator)
	fn.params[0] = new_proj(fn, TY_CTRL, fn.start, 0)
	fn.params[1] = new_proj(fn, TY_MEM, fn.start, 1)

	fn.meta.entry_ctrl = fn.params[0]
	fn.meta.curr_ctrl = fn.params[0]
	fn.meta.curr_mem = fn.params[1]

	fn.end.inputs[0] = fn.meta.curr_ctrl

	for i in 0..<len(proto.params) {
		fn.params[i + 2] = new_proj(fn, proto.params[i].type, fn.start, i + 1)
	}

	return fn
}

@(private = "file")
set_input :: proc(n: ^Node, i: int, v: ^Node) {
	n.inputs[i] = v
	append(&v.users, User { n, i } )
}

new_region :: proc(fn: ^Function, name: string) -> ^Node {
	n := new_node(fn, .Region, TY_CTRL, 1)
	set_input(n, 0, fn.meta.curr_ctrl)
	return n
}

new_extra :: proc($T: typeid, fn: ^Function) -> ^T {
	e := new(T, fn.allocator)
	e.extra.derived = e
	return e
}

new_proj :: proc(fn: ^Function, type: Type, src_node: ^Node, proj_idx: int) -> ^Node {
	proj := new_node(fn, .Proj, type, 1)
	set_input(proj, 0, src_node)

	extra := new_extra(ProjExtra, fn)
	extra.idx = proj_idx

	proj.extra = extra

	return proj
}


new_node :: proc(fn: ^Function, kind: NodeKind, type: Type, input_count: int) -> ^Node {
	n, _ := new(Node, fn.allocator)
	n.kind = kind
	n.gvn = u32(fn.node_count)
	n.type = type
	inputs, _ := make([]^Node, input_count, fn.allocator)
	n.inputs = inputs

	fn.node_count += 1

	return n
}

new_int_const :: proc(fn: ^Function, type: Type, val: IntConstVal) -> ^Node {
	n := new_node(fn, .IntConst, type, 1)
	set_input(n, 0, fn.start)
	extra := new_extra(IntConst, fn)
	extra.val = val
	n.extra = extra
	return n
}

new_float_const :: proc(fn: ^Function, type: Type, val: FloatConstVal) -> ^Node {
	n: ^Node
	switch v in val {
		case f32:
			n = new_node(fn, .F32Const, type, 1)
		case f64:
			n = new_node(fn, .F64Const, type, 1)
	}
	set_input(n, 0, fn.start)
	extra := new_extra(FloatConst, fn)
	extra.val = val
	n.extra = extra
	return n
}

add_local :: proc(fn: ^Function, size: int, align: int) -> ^Node {
	n := new_node(fn, .Local, TY_PTR, 1)
	set_input(n, 0, fn.start)

	local := new_extra(LocalExtra, fn)
	local.size = size
	local.align = align

	n.extra = local
	return n
}

add_sym :: proc(fn: ^Function, s: ^Symbol) -> ^Node {
	n := new_node(fn, .Symbol, TY_PTR, 1)
	set_input(n, 0, fn.start)

	symbol := new_extra(SymbolExtra, fn)
	symbol.sym = s

	n.extra = symbol

	return n
}

@(private = "file")
transfer_control :: proc(fn: ^Function, new_ctrl: ^Node) -> ^Node {
	old := fn.meta.curr_ctrl
	fn.meta.curr_ctrl = new_ctrl
	fn.end.inputs[0] = new_ctrl
	return old
}

@(private = "file")
insert_mem_effect :: proc(fn: ^Function, new_mem: ^Node) -> ^Node {
	old := fn.meta.curr_mem
	fn.meta.curr_mem = new_mem
	return old
}

set_control :: proc(fn: ^Function, ctrl: ^Node) {
	assert(ty_is_ctrl(ctrl.type))
	fn.meta.curr_ctrl = ctrl
	fn.end.inputs[0] = ctrl
}

RegisterClass :: enum {
	IntRegister, // rdi, rsi, etc...
	VectorRegister, // xmm0...
	StackSlot, // structs that can't fit / aggregate return
}


insr_call :: proc(fn: ^Function, target: ^Node, proto: ^FunctionProto, params: []^Node) -> ^Node
{
	n := new_node(fn, .Call, TY_TUPLE, 3 + len(params))

	ctrl_proj := new_proj(fn, TY_CTRL, n, 0)
	mem_proj := new_proj(fn, TY_MEM, n, 1)

	set_input(n, 0, transfer_control(fn, ctrl_proj))
	set_input(n, 1, insert_mem_effect(fn, mem_proj))
	set_input(n, 2, target) // the symbol of the function we want to call
	for p, i in params {
		set_input(n, 3 + i, p)
	}

	extra := new_extra(CallExtra, fn)
	extra.projs = make([]^Node, len(proto.returns) + 2, fn.allocator)
	extra.proto = proto

	extra.projs[0] = ctrl_proj
	extra.projs[1] = mem_proj

	for r, i in proto.returns {
		extra.projs[i + 2] = new_proj(fn, r.type, n, 2 + i)
	}

	n.extra = extra

	return n
}

// FIXME(RD): This stuff is assuming windows-amd64 abi. There's probably some fucked shit going on with sys-v that we should support
get_debug_type_register_class :: proc(dbg_ty: ^DebugType) -> RegisterClass {
	size := debug_type_get_size(dbg_ty)
	if size == 1 || size == 2 || size == 4 || size == 8 {
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

	has_aggregate_return := false
	additional_returns := 0
	if len(d.returns) > 0 {
		primary_return_reg := get_debug_type_register_class(d.returns[0])
		has_aggregate_return = primary_return_reg == .StackSlot
		additional_returns = len(d.returns) - 1
	}

	aggregate_return_offset := 1 if has_aggregate_return else 0

	sync.lock(&m.allocator_lock)
	defer sync.unlock(&m.allocator_lock)

	proto, _ := new(FunctionProto, m.allocator)
	proto.params = make([]FunctionParam, len(d.params) + aggregate_return_offset + additional_returns, m.allocator)
	for p, i in d.params {
		reg := get_debug_type_register_class(p.field_ty)
		t := get_type_with_register_class(reg, p.field_ty)

		proto.params[aggregate_return_offset + i].name = p.name
		proto.params[aggregate_return_offset + i].type = t
		proto.params[aggregate_return_offset + i].debug_type = p.field_ty
	}

	for i in 0..< additional_returns {
		proto.params[aggregate_return_offset + len(d.params) + i].name = "$in_ret"
		proto.params[aggregate_return_offset + len(d.params) + i].type = TY_PTR
		proto.params[aggregate_return_offset + len(d.params) + i].debug_type = d.returns[1 + i]
	}

	if len(d.returns) > 0 && !has_aggregate_return {
		proto.returns = make([]FunctionParam, 1, m.allocator)
		r := d.returns[0]
		reg := get_debug_type_register_class(r)
		assert(reg != .StackSlot)
		t := get_type_with_register_class(reg, r)

		proto.returns[0].name = "$ret"
		proto.returns[0].type = t
		proto.returns[0].debug_type = r
	}

	return proto
}

insr_br :: proc(fn: ^Function, cond: ^Node, then: ^Node, else_l: ^Node) {
	assert(ty_is_bool(cond.type))
	assert(ty_is_ctrl(then.type))
	assert(ty_is_ctrl(else_l.type))
	n := new_node(fn, .Branch, TY_CTRL, 4)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, cond)
	set_input(n, 2, then)
	set_input(n, 3, else_l)
}

insr_goto :: proc(fn: ^Function, to: ^Node) {
	assert(ty_is_ctrl(to.type))
	n := new_node(fn, .Goto, TY_CTRL, 2)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, to)
}

insr_ret :: proc(fn: ^Function, val: ^Node) {
	n := new_node(fn, .Return, TY_CTRL, 3)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, fn.meta.curr_mem)
	set_input(n, 2, val)
}

insr_phi :: proc(fn: ^Function, a: ^Node, b: ^Node) -> ^Node {
	assert(ty_equal(a.type, b.type), "phi parameter type mismatch")
	n := new_node(fn, .Phi, a.type, 4)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, fn.meta.curr_mem)
	set_input(n, 2, a)
	set_input(n, 3, b)
	return n
}

insr_load :: proc(fn: ^Function, t: Type, addr: ^Node, is_volatile: bool) -> ^Node {
	if is_volatile {
		// volatile reads need to project out a new memory effect (mmap'd IO for instance)
		n := new_node(fn, .VolatileRead, TY_TUPLE, 3)

		mem := new_proj(fn, TY_MEM, n, 0)
		data := new_proj(fn, t, n, 1)

		set_input(n, 0, fn.meta.curr_ctrl)
		set_input(n, 1, insert_mem_effect(fn, mem))
		set_input(n, 2, addr)

		return data
	}

	n := new_node(fn, .Load, t, 3)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, fn.meta.curr_mem)
	set_input(n, 2, addr)

	return n
}

insr_store :: proc(fn: ^Function, addr: ^Node, val: ^Node, is_volatile: bool) -> ^Node {
	n: ^Node

	if is_volatile {
		n = new_node(fn, .VolatileWrite, TY_MEM, 4)
	} else {
		n = new_node(fn, .Store, TY_MEM, 4)
	}

	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, insert_mem_effect(fn, n))
	set_input(n, 2, addr)
	set_input(n, 3, val)

	return n
}

insr_memcpy :: proc(fn: ^Function, dst: ^Node, src: ^Node, count: ^Node) -> ^Node {
	assert(ty_is_ptr(dst.type))
	assert(ty_is_ptr(src.type))

	n := new_node(fn, .MemCpy, TY_MEM, 5)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, insert_mem_effect(fn, n))
	set_input(n, 2, dst)
	set_input(n, 3, src)
	set_input(n, 4, count)

	return n
}

insr_memset :: proc(fn: ^Function, dst: ^Node, val: ^Node, count: ^Node) -> ^Node {
	assert(ty_is_ptr(dst.type))
	assert(ty_equal(val.type, TY_I8))

	n := new_node(fn, .MemSet, TY_MEM, 5)
	set_input(n, 0, fn.meta.curr_ctrl)
	set_input(n, 1, insert_mem_effect(fn, n))
	set_input(n, 2, dst)
	set_input(n, 3, val)
	set_input(n, 4, count)

	return n
}

insr_getmemberptr :: proc(fn: ^Function, base: ^Node, dbg_type: ^DebugType, member_name: string) -> ^Node {
	assert(ty_is_ptr(base.type))
	mem_offset := debug_type_get_member_offset(dbg_type, member_name)
	assert(mem_offset != -1)

	offset := new_int_const(fn, TY_PTR, i64(mem_offset))

	n := new_node(fn, .GetMemberPtr, TY_PTR, 3)
	set_input(n, 1, base)
	set_input(n, 2, offset)
	return n
}


@(private = "file")
insr_binop :: proc(fn: ^Function, kind: NodeKind, lhs: ^Node, rhs: ^Node) -> ^Node {
	assert(ty_equal(lhs.type, rhs.type), "binop operand type mismatch")
	n := new_node(fn, kind, lhs.type, 3)
	set_input(n, 1, lhs)
	set_input(n, 2, rhs)
	return n
}

insr_and :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .And, lhs, rhs)
}

insr_or :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Or, lhs, rhs)
}

insr_xor :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .XOr, lhs, rhs)
}

insr_add :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Add, lhs, rhs)
}

insr_sub :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Add, lhs, rhs)
}

insr_mul :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Add, lhs, rhs)
}

insr_shl :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Shl, lhs, rhs)
}

insr_shr :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Shr, lhs, rhs)
}

insr_sar :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Sar, lhs, rhs)
}

insr_rol :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Rol, lhs, rhs)
}

insr_ror :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .Ror, lhs, rhs)
}

insr_udiv :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .UDiv, lhs, rhs)
}

insr_sdiv :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .SDiv, lhs, rhs)
}

insr_umod :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .UMod, lhs, rhs)
}

insr_smod :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .SMod, lhs, rhs)
}

insr_fadd :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FAdd, lhs, rhs)
}

insr_fsub :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FSub, lhs, rhs)
}

insr_fmul :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FMul, lhs, rhs)
}

insr_fdiv :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FDiv, lhs, rhs)
}

insr_fmax :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FMax, lhs, rhs)
}

insr_fmin :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_binop(fn, .FMin, lhs, rhs)
}

@(private = "file")
insr_cmp :: proc(fn: ^Function, kind: NodeKind, lhs: ^Node, rhs: ^Node) -> ^Node {
	assert(ty_equal(lhs.type, rhs.type), "compare operand type mismatch")
	n := new_node(fn, kind, TY_BOOL, 3)
	set_input(n, 1, lhs)
	set_input(n, 2, rhs)
	return n
}

insr_cmp_eq :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpEq, lhs, rhs)
}

insr_cmp_ne :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpNeq, lhs, rhs)
}

insr_cmp_ult :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpULt, lhs, rhs)
}

insr_cmp_ule :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpULe, lhs, rhs)
}

insr_cmp_ugt :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpULt, rhs, lhs)
}

insr_cmp_uge :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpULe, rhs, lhs)
}

insr_cmp_slt :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpSLt, lhs, rhs)
}

insr_cmp_sle :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpSLe, lhs, rhs)
}

insr_cmp_sgt :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpSLt, rhs, lhs)
}

insr_cmp_sge :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpSLe, rhs, lhs)
}

insr_cmp_flt :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpFLt, lhs, rhs)
}

insr_cmp_fle :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpFLe, lhs, rhs)
}

insr_cmp_fgt :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpFLt, rhs, lhs)
}

insr_cmp_fge :: proc(fn: ^Function, lhs: ^Node, rhs: ^Node) -> ^Node {
	return insr_cmp(fn, .CmpFLe, rhs, lhs)
}

@(private = "file")
insr_unary :: proc(fn: ^Function, kind: NodeKind, type: Type, v: ^Node) -> ^Node {
	n := new_node(fn, kind, type, 2)
	set_input(n, 1, v)
	return n
}

insr_not :: proc(fn: ^Function, v: ^Node) -> ^Node {
	return insr_unary(fn, .Not, v.type, v)
}

insr_neg :: proc(fn: ^Function, v: ^Node) -> ^Node {
	return insr_unary(fn, .Negate, v.type, v)
}


Node :: struct {
	kind:   NodeKind,
	type:   Type,
	gvn:    u32,
	inputs: []^Node,
	users:  [dynamic]User,
	extra:  ^NodeExtra,
}

User :: struct {
	n: ^Node,
	slot: int,
}

IntConstVal :: union { u64, i64 }
IntConst :: struct {
	using extra: NodeExtra,
	val: IntConstVal,
}

FloatConstVal :: union { f32, f64 }
FloatConst :: struct {
	using extra: NodeExtra,
	val: FloatConstVal,
}

CallExtra :: struct {
	using extra: NodeExtra,
	proto: ^FunctionProto,
	projs: []^Node,
}

LocalExtra :: struct {
	using extra: NodeExtra,
	size: int,
	align: int,
}

SymbolExtra :: struct {
	using extra: NodeExtra,
	sym: ^Symbol,
}

ProjExtra :: struct {
	using extra: NodeExtra,
	idx: int,
}

AnyExtra :: union {
	^CallExtra,
	^LocalExtra,
	^SymbolExtra,
	^ProjExtra,
	^IntConst,
	^FloatConst,
}

NodeExtra :: struct {
	tag: string,
	derived: AnyExtra,
}

NodeKind :: enum {
	Start,
	End,

	Region,
	Proj,

	IntConst,
	F32Const,
	F64Const,

	Local,
	Symbol,

	Return,
	Call,
	Branch,
	Goto,
	Phi,

	Load,
	Store,
	MemCpy,
	MemSet,
	VolatileRead,
	VolatileWrite,
	GetMemberPtr,

	And,
	Or,
	XOr,

	Add,
	Sub,
	Mul,

	Shl,
	Shr,
	Sar,
	Rol,
	Ror,
	UDiv,
	SDiv,
	UMod,
	SMod,

	FAdd,
	FSub,
	FMul,
	FDiv,
	FMax,
	FMin,

	CmpEq,
	CmpNeq,
	CmpULt,
	CmpULe,
	CmpSLt,
	CmpSLe,
	CmpFLt,
	CmpFLe,

	Not,
	Negate,
}

