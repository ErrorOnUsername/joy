package epoch

import "core:mem"
import "core:sync"


FunctionParam :: struct {
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

Function :: struct {
	using symbol: Symbol,
	pool: mem.Dynamic_Pool,
	allocator: mem.Allocator,
	proto: ^FunctionProto,
	params: []^Node,
	start: ^Node,
	end: ^Node,
	current_control: ^Node,
}

Symbol :: struct {
	name: string,
	linkage: Linkage,
	derived_symbol: AnySymbol,
}

AnySymbol :: union {
	^Function,
}

new_symbol :: proc(m: ^Module, $T: typeid, name: string) -> ^T {
	sym, _ := new(T, m.allocator)
	sym.derived_symbol = sym
	sym.name = name
	return sym
}


new_function :: proc(m: ^Module, name: string, proto: ^FunctionProto) -> ^Function {
	fn := new_symbol(m, Function, name)
	mem.dynamic_pool_init(&fn.pool)
	fn.allocator = mem.dynamic_pool_allocator(&fn.pool)

	fn.start = new_node(fn, .Start, TY_TUPLE, 0)

	fn.proto = proto

	fn.current_control = new_proj(fn, TY_CTRL, fn.start, 0)

	fn.params = make([]^Node, len(proto.params) + 1, fn.allocator)
	fn.params[0] = fn.current_control

	for i in 0..<len(proto.params) {
		fn.params[i + 1] = new_proj(fn, proto.params[i].type, fn.start, i + 1)
	}

	return fn
}

new_function_proto :: proc(m: ^Module, params: []FunctionParam, returns: []FunctionParam) -> ^FunctionProto {
	proto, _ := new(FunctionProto, m.allocator)
	proto.params = params
	proto.returns = returns
	return proto
}

new_proj :: proc(fn: ^Function, type: Type, src_node: ^Node, proj_idx: int) -> ^Node {
	proj := new_node(fn, .Proj, type, 1)
	proj.inputs[0] = src_node
	return proj
}


new_node :: proc(fn: ^Function, kind: NodeKind, type: Type, input_count: int) -> ^Node {
	n, _ := new(Node, fn.allocator)
	n.kind = kind
	n.type = type
	inputs, _ := make([]^Node, input_count, fn.allocator)
	n.inputs = inputs
	return n
}


add_local :: proc(fn: ^Function) -> ^Node {
	n := new_node(fn, .Local, TY_PTR, 2)
	return n
}

insr_call :: proc(fn: ^Function, target: ^Node, proto: ^FunctionProto, params: []^Node) -> []^Node
{
	n := new_node(fn, .Call, TY_TUPLE, 3 + len(params))
	n.inputs[0] = fn.current_control
	n.inputs[2] = target
	for p, i in params {
		n.inputs[3 + i] = p
	}

	extra, _ := new(CallExtra, fn.allocator)
	extra.projs = make([]^Node, max(len(proto.returns) + 1, 3), fn.allocator)
	extra.proto = proto

	ctrl_proj := new_proj(fn, TY_CTRL, n, 0)
	mem_proj := new_proj(fn, TY_MEM, n, 1)

	extra.projs[0] = ctrl_proj
	extra.projs[1] = mem_proj

	for r, i in proto.returns {
		extra.projs[i + 2] = new_proj(fn, r.type, n, 2 + i)
	}

	fn.current_control = ctrl_proj

	return extra.projs[2:]
}

insr_br :: proc(fn: ^Function, to: ^Node) -> ^Node {
	n := new_node(fn, .Branch, TY_CTRL, 3)
	return n
}

insr_phi :: proc(fn: ^Function, a: ^Node, b: ^Node) -> ^Node {
	assert(ty_equal(a.type, b.type), "phi parameter type mismatch")
	n := new_node(fn, .Phi, a.type, 4)
	return n
}

insr_load :: proc(fn: ^Function, t: Type, addr: ^Node, is_volatile: bool) -> ^Node {
	n: ^Node

	if is_volatile {
		n = new_node(fn, .VolatileRead, t, 3)
	} else {
		n = new_node(fn, .Load, t, 3)
	}

	return n
}

insr_store :: proc(fn: ^Function, addr: ^Node, val: ^Node, is_volatile: bool) -> ^Node {
	n: ^Node

	if is_volatile {
		n = new_node(fn, .VolatileWrite, TY_MEM, 4)
	} else {
		n = new_node(fn, .Store, TY_MEM, 4)
	}

	return n
}

insr_memcpy :: proc(fn: ^Function, dst: ^Node, src: ^Node, count: ^Node) -> ^Node {
	n := new_node(fn, .MemCpy, TY_MEM, 5)
	return n
}

insr_memset :: proc(fn: ^Function, dst: ^Node, src: ^Node, count: ^Node, val: ^Node) -> ^Node {
	n := new_node(fn, .MemSet, TY_MEM, 6)
	return n
}


@(private = "file")
insr_binop :: proc(fn: ^Function, kind: NodeKind, lhs: ^Node, rhs: ^Node) -> ^Node {
	assert(ty_equal(lhs.type, rhs.type), "binop operand type mismatch")
	n := new_node(fn, kind, lhs.type, 3)
	n.inputs[1] = lhs
	n.inputs[2] = rhs
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
	n.inputs[1] = lhs
	n.inputs[2] = rhs
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
	n.inputs[1] = v
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
	inputs: []^Node,
	outputs: ^NodeOutput,
	extra:   NodeExtra,
}

CallExtra :: struct {
	proto: ^FunctionProto,
	projs: []^Node,
}

NodeExtra :: union {
	^CallExtra,
}

NodeOutput :: struct {
	user: ^Node,
	next: ^NodeOutput,
}

NodeKind :: enum {
	Start,
	End,

	Region,
	Proj,

	Local,

	Call,
	Branch,
	Phi,

	Load,
	Store,
	MemCpy,
	MemSet,
	VolatileRead,
	VolatileWrite,

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
