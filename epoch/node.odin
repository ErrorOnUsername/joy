package epoch

import "core:mem"
import "core:sync"


Function :: struct {
	using symbol: Symbol,
	arena: mem.Arena,
	allocator: mem.Allocator,
	start: ^Node,
	end: ^Node,
	current_control: ^Node,
}

Symbol :: struct {
	name: string,
	derived_symbol: AnySymbol,
}

AnySymbol :: union {
	^Function,
}

new_symbol :: proc( ctx: EpochContext, $T: typeid, name: string ) -> ^T {
	sym := mem.new( T, ctx.global_allocator )
	sym.derived_symbol = sym
	sym.name = name

	return sym
}


new_node :: proc() -> Node {
	return nil
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

