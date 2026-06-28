package opto


AArch64Reg :: enum {
	X0,  X1,  X2,  X3,  X4,  X5,  X6,  X7,  X8,  X9,  X10, X11,
	X12, X13, X14, X15, X16, X17, X18, X19, X20, X21, X22, X23,
	X24, X25, X26, X27, X28, X29, X30, RSP,

	D0,  D1,  D2,  D3,  D4,  D5,  D6,  D7,  D8,  D9,  D10, D11,
	D12, D13, D14, D15, D16, D17, D18, D19, D20, D21, D22, D23,
	D24, D25, D26, D27, D28, D29, D30, D31,

	Flags,

	MAX_REG,
}

AArch64RegMask :: bit_set[AArch64Reg; i128]

impl_aarch64 := ArchImpl {
	reg_names = {
		"X0",  "X1",  "X2",  "X3",  "X4",  "X5",  "X6",  "X7",  "X8",  "X9",  "X10", "X11",
		"X12", "X13", "X14", "X15", "X16", "X17", "X18", "X19", "X20", "X21", "X22", "X23",
		"X24", "X25", "X26", "X27", "X28", "X29", "X30", "RSP",

		"D0",  "D1",  "D2",  "D3",  "D4",  "D5",  "D6",  "D7",  "D8",  "D9",  "D10", "D11",
		"D12", "D13", "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23",
		"D24", "D25", "D26", "D27", "D28", "D29", "D30", "D31",

		"Flags",
	},
	abi = {
		{
			param_order = .LeftToRight,
			param_stack_order = .LeftToRight,
			int_param_regs = {
				transmute(RegisterMask)AArch64RegMask{ .X0 }, transmute(RegisterMask)AArch64RegMask{ .X1 }, transmute(RegisterMask)AArch64RegMask{ .X2 }, transmute(RegisterMask)AArch64RegMask{ .X3 },
				transmute(RegisterMask)AArch64RegMask{ .X4 }, transmute(RegisterMask)AArch64RegMask{ .X5 }, transmute(RegisterMask)AArch64RegMask{ .X6 }, transmute(RegisterMask)AArch64RegMask{ .X7 }
			},
			float_param_regs = {
				transmute(RegisterMask)AArch64RegMask{ .D0 }, transmute(RegisterMask)AArch64RegMask{ .D1 }, transmute(RegisterMask)AArch64RegMask{ .D2 }, transmute(RegisterMask)AArch64RegMask{ .D3 },
				transmute(RegisterMask)AArch64RegMask{ .D4 }, transmute(RegisterMask)AArch64RegMask{ .D5 }, transmute(RegisterMask)AArch64RegMask{ .D6 }, transmute(RegisterMask)AArch64RegMask{ .D7 }
			},
			return_regs = transmute(RegisterMask)AArch64RegMask{ .X0 },
			caller_saved_regs = transmute(RegisterMask)AArch64RegMask{
				.X9, .X10, .X11, .X12, .X13, .X14, .X15,
				.D16, .D17, .D18, .D19, .D20, .D21, .D22, .D23, .D24, .D25, .D26, .D27, .D28, .D29, .D30, .D31
			},
			callee_saved_regs = transmute(RegisterMask)AArch64RegMask{
				.X19, .X20, .X21, .X22, .X23, .X24, .X25, .X26, .X27, .X28,
				.D8, .D9, .D10, .D11, .D12, .D13, .D14, .D15
			},
		},
	},
	select = aarch64_select,
	encode = aarch64_encode,
	encoding_size = aarch64_encoding_size,
	patch_local_relo = aarch64_patch_local_relo,
	get_callee_save_regmask = aarch64_get_callee_save_regmask,
	get_src_regmask = aarch64_get_src_regmask,
	get_dst_regmask = aarch64_get_dst_regmask,
	get_kill_regmask = aarch64_get_kill_regmask,
	is_two_address_op = aarch64_is_two_address_op,
	get_two_address_index = aarch64_get_two_address_index,
}

aarch64_select :: proc(fn: ^Function, n: ^Node) -> MachineOp {
	assert(n.uop == 0)
	match := match_table[n.kind]
	for pred in match.predicates {
		if pred.pred == nil || pred.pred(n) {
			log(fn, "{}{} -> aarch64.{}", n.kind, n.gvn, pred.insr)
			return MachineOp(pred.insr)
		}
	}

	return INVALID_OP
}

aarch64_encode :: proc(fn: ^Function, n: ^Node, bm: ^BlockMap) -> bool {
	panic("impl encode")
}

aarch64_encoding_size :: proc(n: ^Node, delta_from_start_to_target: int) -> int {
	panic("impl encoding size")
}

aarch64_patch_local_relo :: proc(fn: ^Function, n: ^Node, start: int, delta_from_start_to_target: int) {
	panic("impl patch_local_relo")
}

aarch64_get_callee_save_regmask ::  proc(ctx: ^RegAllocContext) -> RegisterMask {
	return impl_aarch64.abi[0].callee_saved_regs
}

aarch64_get_src_regmask :: proc(ctx: ^RegAllocContext, n: ^Node, from: int) -> RegisterMask {
	panic("impl get_src_regmask")
}

aarch64_get_dst_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	panic("impl get_dst_regmask")
}

aarch64_get_kill_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	panic("impl get_kill_regmask")
}

aarch64_is_two_address_op :: proc(ctx: ^RegAllocContext, n: ^Node) -> bool {
	panic("impl is_two_address_op")
}

aarch64_get_two_address_index :: proc(ctx: ^RegAllocContext, n: ^Node) -> int {
	panic("impl get_two_address_index")
}

@(private = "file")
InsrMatchProc :: #type proc (n: ^Node) -> bool
@(private = "file")
InsrMatchPred :: struct {
	insr: Amd64Insr,
	pred: InsrMatchProc,
}
@(private = "file")
InsrMatch :: struct {
	predicates: []InsrMatchPred,
}

aarch64_is_reg_type :: proc(n: ^Node) -> bool {
	return ty_is_int(n.type) || ty_is_float(n.type) || ty_is_ptr(n.type)
}

aarch64_reg_format :: proc(n: ^Node) -> bool {
	for input in n.inputs[node_get_data_start(n):] {
		if !aarch64_is_reg_type(input) {
			return false
		}
	}
	return true
}

aarch64_imm_format :: proc(n: ^Node) -> bool {
	assert(len(n.inputs) == 3) // this only works for binops
	return aarch64_is_reg_type(n.inputs[1]) && is_const_node(n.inputs[2])
}

@(private = "file")
match_table := [NodeKind]InsrMatch {
	.Start = { { { insr = .Start } } },
	.End = {},
	.Region = {},
	.Param = { { { insr = .Param } } },
	.Proj = { { { insr = .Proj } } },
	.IntConst = {},
	.F32Const = {},
	.F64Const = {},
	.Local = { { { insr = .Local } } },
	.Symbol = {},
	.CalleeSave = {},
	.Return = { { { insr = .Ret } } },
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
	.GetMemberPtr = { { { insr = .GetMemberPtr } } },
	.And = { { { insr = .AndImm, pred = aarch64_imm_format }, { insr = .And, pred = aarch64_reg_format } } },
	.Or = { { { insr = .OrImm, pred = aarch64_imm_format }, { insr = .Or, pred = aarch64_reg_format } } },
	.XOr = { { { insr = .XOrImm, pred = aarch64_imm_format }, { insr = .XOr, pred = aarch64_reg_format } } },
	.Add = { { { insr = .AddImm, pred = aarch64_imm_format }, { insr = .Add, pred = aarch64_reg_format } } },
	.Sub = { { { insr = .SubImm, pred = aarch64_imm_format }, { insr = .Sub, pred = aarch64_reg_format } } },
	.Mul = { { { insr = .MulImm, pred = aarch64_imm_format }, { insr = .Mul, pred = aarch64_reg_format } } },
	.Shl = { { { insr = .ShlImm, pred = aarch64_imm_format }, { insr = .Shl, pred = aarch64_reg_format } } },
	.Shr = { { { insr = .ShrImm, pred = aarch64_imm_format }, { insr = .Shr, pred = aarch64_reg_format } } },
	.Sar = { { { insr = .SarImm, pred = aarch64_imm_format }, { insr = .Sar, pred = aarch64_reg_format } } },
	.Rol = {},
	.Ror = {},
	.UDiv = { { { insr = .DivImm, pred = amd64_imm_format }, { insr = .Div, pred = amd64_reg_format } } },
	.SDiv = { { { insr = .DivImm, pred = amd64_imm_format }, { insr = .Div, pred = amd64_reg_format } } },
	.UMod = {},
	.SMod = {},
	.FAdd = { { { insr = .AddF } } },
	.FSub = { { { insr = .SubF } } },
	.FMul = { { { insr = .MulF } } },
	.FDiv = { { { insr = .DivF } } },
	.FMax = {},
	.FMin = {},
	.CmpEq = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpNeq = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpULt = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpULe = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpSLt = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpSLe = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpFLt = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpFLe = { { { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.Not = {},
	.Negate = {},
}

AArch64Insr :: enum(u32) {
	Invalid,
	Start,
	Param,
	Proj,
	Local,
	Ret,
	Call,
	Jmp,
	Load,
	GetMemberPtr,
	Store,
	Add,
	AddImm,
	Sub,
	SubImm,
	Mul,
	MulImm,
	Div,
	DivImm,
	AddF,
	SubF,
	MulF,
	DivF,
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
}
