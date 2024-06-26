package epoch

import "core:mem"


Function :: struct
{
	arena: mem.Arena,
	allocator: mem.Allocator,
	start: ^Node,
	end: ^Node,
	current_control: ^Node,
}

Node :: struct
{
	kind:   NodeKind,
	type:   Type,
	inputs: []^Node,
	outputs: ^NodeOutput,
}

NodeOutput :: struct
{
	user: ^Node,
	next: ^NodeOutput,
}

NodeKind :: enum
{
	Start,
	End,

	Region,

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

create_function :: proc(ctx: EpochContext) -> ^Function
{
}
