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
	arena: mem.Arena,
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

	Call,
	Branch,
	Phi,

	Load,
	Store,
	MemCpy,
	MemSet,
	Read,
	Write,

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
