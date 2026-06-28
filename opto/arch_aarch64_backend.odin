package opto

@(private = "file")
GPR_READ_MASK := AArch64RegMask {
	.X0,  .X1,  .X2,  .X3,  .X4,  .X5,  .X6,  .X7,  .X8,  .X9,  .X10, .X11,
	.X12, .X13, .X14, .X15, .X16, .X17, .X18, .X19, .X20, .X21, .X22, .X23,
	.X24, .X25, .X26, .X27, .X28, .X29, .X30, .SP,
}
@(private = "file")
GPR_WRITE_MASK := AArch64RegMask { // The same as READ just no SP
	.X0,  .X1,  .X2,  .X3,  .X4,  .X5,  .X6,  .X7,  .X8,  .X9,  .X10, .X11,
	.X12, .X13, .X14, .X15, .X16, .X17, .X18, .X19, .X20, .X21, .X22, .X23,
	.X24, .X25, .X26, .X27, .X28, .X29, .X30,
}
@(private = "file")
XMM_MASK := AArch64RegMask {
	.D0,  .D1,  .D2,  .D3,  .D4,  .D5,  .D6,  .D7,  .D8,  .D9,  .D10, .D11,
	.D12, .D13, .D14, .D15, .D16, .D17, .D18, .D19, .D20, .D21, .D22, .D23,
	.D24, .D25, .D26, .D27, .D28, .D29, .D30, .D31,
}
@(private = "file")
FLAGS_MASK := AArch64RegMask { .Flags }
@(private = "file")
SPILL_MASK := RegisterMask(-i128(1 << uint(AArch64Reg.MAX_REG)))

AArch64Reg :: enum {
	X0,  X1,  X2,  X3,  X4,  X5,  X6,  X7,  X8,  X9,  X10, X11,
	X12, X13, X14, X15, X16, X17, X18, X19, X20, X21, X22, X23,
	X24, X25, X26, X27, X28, X29, X30, SP,

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
		"X24", "X25", "X26", "X27", "X28", "X29", "X30", "SP",

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
	uop := AArch64Insr(n.uop)
	switch uop {
		case .Invalid:
		case .Start:
			panic("impl start")
		case .Param:
		case .Proj:
		case .Local:
		case .Ret:
			panic("impl ret")
		case .Call:
			panic("impl call")
		case .Jmp:
			panic("impl jmp")
		case .Load:
			panic("impl load")
		case .GetMemberPtr:
			panic("impl getmemberptr")
		case .Store:
			panic("impl store")
		case .Add:
			panic("impl add")
		case .AddImm:
			panic("impl addi")
		case .Sub:
			panic("impl sub")
		case .SubImm:
			panic("impl subi")
		case .Mul:
			panic("impl mul")
		case .MulImm:
			panic("impl muli")
		case .Div:
			panic("impl div")
		case .DivImm:
			panic("impl divi")
		case .AddF:
			panic("impl addf")
		case .SubF:
			panic("impl subf")
		case .MulF:
			panic("impl mulf")
		case .DivF:
			panic("impl divf")
		case .Sal:
			panic("impl sal")
		case .SalImm:
			panic("impl sali")
		case .Sar:
			panic("impl sar")
		case .SarImm:
			panic("impl sari")
		case .Shl:
			panic("impl shl")
		case .ShlImm:
			panic("impl shli")
		case .Shr:
			panic("impl shr")
		case .ShrImm:
			panic("impl shri")
		case .And:
			panic("impl and")
		case .AndImm:
			panic("impl andi")
		case .Or:
			panic("impl or")
		case .OrImm:
			panic("impl ori")
		case .XOr:
			panic("impl xor")
		case .XOrImm:
			panic("impl xori")
		case .Cmp:
			panic("impl cmp")
		case .CmpImm:
			panic("impl cmpi")
	}
	return true
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

aarch64_get_param_regmask :: proc(ctx: ^RegAllocContext, proto: ^FunctionProto, type: Type, idx: int) -> RegisterMask {
	regmask: RegisterMask
	lead_params_of_same_type := 0
	for i in 0..<idx {
		if ty_equal(proto.params[i].type, type) {
			lead_params_of_same_type += 1
		}
	}
	if ty_is_int(type) {
		regmask = impl_aarch64.abi[0].int_param_regs[lead_params_of_same_type]
	} else if ty_is_int(type) {
		regmask = impl_aarch64.abi[0].float_param_regs[lead_params_of_same_type]
	} else {
		panic("unknown param type")
	}
	return regmask
}

aarch64_get_src_regmask :: proc(ctx: ^RegAllocContext, n: ^Node, from: int) -> RegisterMask {
	regmask := transmute(RegisterMask)insr_table[AArch64Insr(n.uop)].in_regmask
	uop := AArch64Insr(n.uop)
	#partial switch uop {
		case .Call:
			// FIXME: If you have too many integer arguments into the function the codegen backend for the lanuage might make some assumptions about the ABI instead of naively just spitting out types...
			// Double check on this because it would fuck up the counts maybe idk. the stack is the stack but still just check.
			param_node := n.inputs[from]
			param_offset := from - 3 // transform to 0..n space to index the register mask out of the 3..n space for the parmeters (see insr_call)
			proto := n.extra.derived.(^CallExtra).proto
			regmask = aarch64_get_param_regmask(ctx, proto, param_node.type, param_offset)
			assert(regmask != 0)
		case .Ret:
			regmask = impl_aarch64.abi[0].return_regs // TODO: There's register splitting on SysV so just make sure all that bullshit works, idk...
		case .Load:
			assert(from == 2) // the slot
			return transmute(RegisterMask)GPR_READ_MASK | SPILL_MASK
		case .Store:
			assert(from == 2 || from == 3)
			if from == 2 { // the slot
				return transmute(RegisterMask)GPR_READ_MASK | SPILL_MASK
			} // others take default
	}
	assert(regmask != 0)
	return regmask
}

aarch64_get_dst_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	table_ent := &insr_table[AArch64Insr(n.uop)]

	if aarch64_is_two_address_op(ctx, n){
		two_addr_lrg := find_live_range(ctx, n.inputs[table_ent.two_address_index])
		return ctx.lrg_store[merge_live_range(ctx, two_addr_lrg, n)].available_mask
	}

	regmask := transmute(RegisterMask)table_ent.out_regmask
	uop := AArch64Insr(n.uop)
	#partial switch uop {
		case .Param:
			start_proj_idx := n.extra.derived.(^ProjExtra).idx
			param_idx := start_proj_idx - 2 // going from the 2..n space to 0..n for the params (see new_function)
			regmask = aarch64_get_param_regmask(ctx, ctx.fn.proto, n.type, param_idx)
		case .Proj:
			regmask = aarch64_get_dst_regmask(ctx, n.inputs[0])
		case .Call:
			regmask = impl_aarch64.abi[0].return_regs
	}
	return regmask // some insrs are allowed to not produce any regs (Stores for example)
}

aarch64_get_kill_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	assert(n != nil)
	assert(arch_is_valid_op(n.uop))
	uop := AArch64Insr(n.uop)
	regmask := transmute(RegisterMask)insr_table[uop].killmap
	#partial switch uop {
		case .Call:
			regmask = impl_aarch64.abi[0].caller_saved_regs
	}
	return regmask // some insrs are allowed to not produce any regs (Stores for example)
}

aarch64_is_two_address_op :: proc(ctx: ^RegAllocContext, n: ^Node) -> bool {
	return false
}

aarch64_get_two_address_index :: proc(ctx: ^RegAllocContext, n: ^Node) -> int {
	panic("impl get_two_address_index")
}

@(private = "file")
InsrMatchProc :: #type proc (n: ^Node) -> bool
@(private = "file")
InsrMatchPred :: struct {
	insr: AArch64Insr,
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
	.UDiv = { { { insr = .DivImm, pred = aarch64_imm_format }, { insr = .Div, pred = aarch64_reg_format } } },
	.SDiv = { { { insr = .DivImm, pred = aarch64_imm_format }, { insr = .Div, pred = aarch64_reg_format } } },
	.UMod = {},
	.SMod = {},
	.FAdd = { { { insr = .AddF } } },
	.FSub = { { { insr = .SubF } } },
	.FMul = { { { insr = .MulF } } },
	.FDiv = { { { insr = .DivF } } },
	.FMax = {},
	.FMin = {},
	.CmpEq = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpNeq = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpULt = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpULe = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpSLt = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpSLe = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpFLt = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.CmpFLe = { { { insr = .CmpImm, pred = aarch64_imm_format }, { insr = .Cmp, pred = aarch64_reg_format } } },
	.Not = {},
	.Negate = {},
}

@(private = "file")
InsrTableEntry :: struct {
	in_regmask:        AArch64RegMask,
	out_regmask:       AArch64RegMask,
	two_address_index: int,
	killmap:           AArch64RegMask,
}

@(private = "file")
insr_table := [AArch64Insr]InsrTableEntry {
	.Invalid = { },
	.Start = { in_regmask = {}, out_regmask = {} },
	.Param = { in_regmask = {}, out_regmask = {} },
	.Proj = { in_regmask = {}, out_regmask = {} },
	.Local = { in_regmask = {}, out_regmask = transmute(AArch64RegMask)SPILL_MASK },
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {} },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.GetMemberPtr = { in_regmask = GPR_READ_MASK | transmute(AArch64RegMask)SPILL_MASK, out_regmask = GPR_WRITE_MASK },
	.Store = { in_regmask = GPR_READ_MASK, out_regmask = {} },
	.Add = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Sub = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SubImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Mul = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.MulImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Div = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.DivImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.SubF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.MulF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.DivF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.Sal = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SalImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Sar = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SarImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Shl = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.ShlImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Shr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.ShrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.And = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AndImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Or = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.OrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.XOr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.XOrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Cmp = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
	.CmpImm = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
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
