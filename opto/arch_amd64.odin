package opto

import "core:fmt"


Amd64Reg :: enum(RegisterID) {
	RAX, RBX, RCX, RDX, RSI, RDI, RSP, RBP, R8, R9, R10, R11, R12, R13, R14, R15,
	XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15,
	RFLAGS,
}

Amd64RegMask :: bit_set[Amd64Reg]

@(private = "file")
GPR_READ_MASK := Amd64RegMask { .RAX, .RBX, .RCX, .RDX, .RSI, .RDI, .RSP, .RBP, .R8, .R9, .R10, .R11, .R12, .R13, .R14, .R15 }
@(private = "file")
GPR_WRITE_MASK := Amd64RegMask { .RAX, .RBX, .RCX, .RDX, .RSI, .RDI, .RBP, .R8, .R9, .R10, .R11, .R12, .R13, .R14, .R15 }
@(private = "file")
XMM_MASK := Amd64RegMask { .XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5, .XMM6, .XMM7, .XMM8, .XMM9, .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15 }
@(private = "file")
FLAGS_MASK := Amd64RegMask { .RFLAGS }

Amd64ABI :: enum {
	Win64,
	SysV64,
}

impl_amd64 := ArchImpl {
	reg_names = {
		"rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rsp", "rbp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15",
		"xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7", "xmm8", "xmm9", "xmm10", "xmm11", "xmm12", "xmm13", "xmm14", "xmm15",
		"rflags",
	},
	abi = {
		// Win64
		{
			return_regs = transmute(RegisterMask)Amd64RegMask { .RAX },
			caller_saved_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RCX, .RDX, .R8, .R9, .R10, .R11, .XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5 },
			callee_saved_regs = transmute(RegisterMask)Amd64RegMask { .RBX, .RBP, .RDI, .RSI, .RSP, .R12, .R13, .R14, .R15, .XMM6, .XMM7, .XMM8, .XMM9, .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15 },
		},
		// SysV64
		{
			return_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RDX },
			caller_saved_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RDI, .RSI, .RCX, .RDX, .R8, .R9, .R10, .R11 },
			callee_saved_regs = transmute(RegisterMask)Amd64RegMask { .RBX, .RBP, .RSP, .R12, .R13, .R14, .R15, .XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5, .XMM6, .XMM7, .XMM8, .XMM9, .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15 },
		},
	},
	select = amd64_select,
	encode = amd64_encode,
}

MachineNode :: struct {
	uop:         Amd64Insr,
	in_regmask:  Amd64RegMask,
	out_regmask: Amd64RegMask,
}

amd64_select :: proc(fn: ^Function, n: ^Node) -> MachineOp {
	match := match_table[to_node_kind(n.kind)]
	for pred in match.predicates {
		if pred.pred(n) {
			return MachineOp(pred.insr)
		}
	}

	return INVALID_OP
}

amd64_encode :: proc(fn: ^Function, n: ^Node) -> bool {
	fmt.println("test encode")
	return true
}

InsrMatchProc :: #type proc (n: ^Node) -> bool
InsrMatchPred :: struct {
	insr: Amd64Insr,
	pred: InsrMatchProc,
}
InsrMatch :: struct {
	predicates: []InsrMatchPred,
}

amd64_reg_format :: proc(n: ^Node) -> bool {
	return true
}

amd64_imm_format :: proc(n: ^Node) -> bool {
	return true
}

amd64_mem_format :: proc(n: ^Node) -> bool {
	return true
}

match_table := [NodeKind]InsrMatch {
	.Start = {},
	.End = {},
	.Region = {},
	.Proj = {},
	.IntConst = {},
	.F32Const = {},
	.F64Const = {},
	.Local = {},
	.Symbol = {},
	.Return = { { { insr = .Ret, pred = amd64_reg_format } } },
	.Call = { { { insr = .Call } } },
	.Branch = { { { insr = .Jmp } } },
	.Goto = { { { insr = .Jmp } } },
	.Phi = {},
	.Load = { { { insr = .Load } } },
	.Store = { { { insr = .Store } } },
	.MemCpy = {},
	.MemSet = {},
	.VolatileRead = { { { insr = .Load } } },
	.VolatileWrite = { { { insr = .Store } } },
	.GetMemberPtr = {},
	.And = { { { insr = .And, pred = amd64_reg_format }, { insr = .AndImm, pred = amd64_imm_format } } },
	.Or = { { { insr = .Or, pred = amd64_reg_format }, { insr = .OrImm, pred = amd64_imm_format } } },
	.XOr = { { { insr = .XOr, pred = amd64_reg_format }, { insr = .XOrImm, pred = amd64_imm_format } } },
	.Add = { { { insr = .Add, pred = amd64_reg_format }, { insr = .AddImm, pred = amd64_imm_format }, { insr = .AddMem, pred = amd64_mem_format } } },
	.Sub = { { { insr = .Sub, pred = amd64_reg_format }, { insr = .SubImm, pred = amd64_imm_format }, { insr = .SubMem, pred = amd64_mem_format } } },
	.Mul = { { { insr = .Mul, pred = amd64_reg_format }, { insr = .MulImm, pred = amd64_imm_format }, { insr = .MulMem, pred = amd64_mem_format } } },
	.Shl = { { { insr = .Shl, pred = amd64_reg_format }, { insr = .ShlImm, pred = amd64_imm_format } } },
	.Shr = { { { insr = .Shr, pred = amd64_reg_format }, { insr = .ShrImm, pred = amd64_imm_format } } },
	.Sar = { { { insr = .Sar, pred = amd64_reg_format }, { insr = .SarImm, pred = amd64_imm_format } } },
	.Rol = {},
	.Ror = {},
	.UDiv = { { { insr = .Div, pred = amd64_reg_format }, { insr = .DivImm, pred = amd64_imm_format }, { insr = .DivMem, pred = amd64_mem_format } } },
	.SDiv = { { { insr = .Div, pred = amd64_reg_format }, { insr = .DivImm, pred = amd64_imm_format }, { insr = .DivMem, pred = amd64_mem_format } } },
	.UMod = {},
	.SMod = {},
	.FAdd = { { { insr = .AddF, pred = amd64_reg_format }, { insr = .AddFMem, pred = amd64_mem_format } } },
	.FSub = { { { insr = .SubF, pred = amd64_reg_format }, { insr = .SubFMem, pred = amd64_mem_format } } },
	.FMul = { { { insr = .MulF, pred = amd64_reg_format }, { insr = .MulFMem, pred = amd64_mem_format } } },
	.FDiv = { { { insr = .DivF, pred = amd64_reg_format }, { insr = .DivFMem, pred = amd64_mem_format } } },
	.FMax = {},
	.FMin = {},
	.CmpEq = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpNeq = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpULt = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpULe = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpSLt = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpSLe = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpFLt = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.CmpFLe = { { { insr = .Cmp, pred = amd64_reg_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .CmpMem, pred = amd64_mem_format } } },
	.Not = {},
	.Negate = {},
}

InsrTableEntry :: struct {
	in_regmask:  Amd64RegMask,
	out_regmask: Amd64RegMask,
}

insr_table := [Amd64Insr]InsrTableEntry {
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {} },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.Store = { in_regmask = GPR_READ_MASK, out_regmask = {} },
	.Add = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.AddImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.AddMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.Sub = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.SubImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.SubMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.Mul = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.MulImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.MulMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.Div = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.DivImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.DivMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.AddF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.AddFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.SubF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.SubFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.MulF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.MulFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.DivF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.DivFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK },
	.Sal = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.SalImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.Sar = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.SarImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.Shl = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.ShlImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.Shr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.ShrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.And = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.AndImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.Or = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.OrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.XOr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.XOrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK },
	.Cmp = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
	.CmpImm = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
	.CmpMem = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
}

Amd64Insr :: enum {
	Ret,
	Call,
	Jmp,
	Load,
	Store,
	Add,
	AddImm,
	AddMem,
	Sub,
	SubImm,
	SubMem,
	Mul,
	MulImm,
	MulMem,
	Div,
	DivImm,
	DivMem,
	AddF,
	AddFMem,
	SubF,
	SubFMem,
	MulF,
	MulFMem,
	DivF,
	DivFMem,
	Sal,
	SalImm,
	Sar,
	SarImm,
	Shl,
	ShlImm,
	Shr,
	ShrImm,
	And,
	AndImm,
	Or,
	OrImm,
	XOr,
	XOrImm,
	Cmp,
	CmpImm,
	CmpMem,
}

