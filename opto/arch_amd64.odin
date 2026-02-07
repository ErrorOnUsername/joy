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
			param_order = .LeftToRight,
			param_stack_order = .RightToLeft,
			int_param_regs = { transmute(RegisterMask)Amd64RegMask { .RCX }, transmute(RegisterMask)Amd64RegMask { .RDX }, transmute(RegisterMask)Amd64RegMask { .R9 }, transmute(RegisterMask)Amd64RegMask { .R8 } },
			float_param_regs = { transmute(RegisterMask)Amd64RegMask { .XMM0 }, transmute(RegisterMask)Amd64RegMask { .XMM1 }, transmute(RegisterMask)Amd64RegMask { .XMM2 }, transmute(RegisterMask)Amd64RegMask { .XMM3 } },
			return_regs = transmute(RegisterMask)Amd64RegMask { .RAX },
			caller_saved_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RCX, .RDX, .R8, .R9, .R10, .R11, .XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5 },
			callee_saved_regs = transmute(RegisterMask)Amd64RegMask { .RBX, .RBP, .RDI, .RSI, .RSP, .R12, .R13, .R14, .R15, .XMM6, .XMM7, .XMM8, .XMM9, .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15 },
		},
		// SysV64
		{
			param_order = .LeftToRight,
			param_stack_order = .RightToLeft,
			int_param_regs = { transmute(RegisterMask)Amd64RegMask { .RDI }, transmute(RegisterMask)Amd64RegMask { .RSI }, transmute(RegisterMask)Amd64RegMask { .RDX }, transmute(RegisterMask)Amd64RegMask { .RCX }, transmute(RegisterMask)Amd64RegMask { .R8 }, transmute(RegisterMask)Amd64RegMask { .R9 } },
			float_param_regs = { transmute(RegisterMask)Amd64RegMask { .XMM0 }, transmute(RegisterMask)Amd64RegMask { .XMM1 }, transmute(RegisterMask)Amd64RegMask { .XMM2 }, transmute(RegisterMask)Amd64RegMask { .XMM3 }, transmute(RegisterMask)Amd64RegMask { .XMM4 }, transmute(RegisterMask)Amd64RegMask { .XMM5 }, transmute(RegisterMask)Amd64RegMask { .XMM6 }, transmute(RegisterMask)Amd64RegMask { .XMM7 } },
			return_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RDX },
			caller_saved_regs = transmute(RegisterMask)Amd64RegMask { .RAX, .RDI, .RSI, .RCX, .RDX, .R8, .R9, .R10, .R11 },
			callee_saved_regs = transmute(RegisterMask)Amd64RegMask { .RBX, .RBP, .RSP, .R12, .R13, .R14, .R15, .XMM0, .XMM1, .XMM2, .XMM3, .XMM4, .XMM5, .XMM6, .XMM7, .XMM8, .XMM9, .XMM10, .XMM11, .XMM12, .XMM13, .XMM14, .XMM15 },
		},
	},
	select = amd64_select,
	encode = amd64_encode,
	get_callee_save_regmask = amd64_get_callee_save_regmask,
	get_src_regmask = amd64_get_src_regmask,
	get_dst_regmask = amd64_get_dst_regmask,
	get_kill_regmask = amd64_get_kill_regmask,
	is_two_address_op = amd64_is_two_address_op,
	get_two_address_index = amd64_get_two_address_index,
}

MachineNode :: struct {
	uop:          Amd64Insr,
	in_regmask:   Amd64RegMask,
	out_regmask:  Amd64RegMask,
	kill_regmask: Amd64RegMask,
}

amd64_select :: proc(fn: ^Function, n: ^Node) -> MachineOp {
	match := match_table[n.kind]
	for pred in match.predicates {
		if pred.pred == nil || pred.pred(n) {
			log(fn, "{}{} -> amd64.{}", n.kind, n.gvn, pred.insr)
			return MachineOp(pred.insr)
		}
	}

	return INVALID_OP
}

amd64_encode :: proc(fn: ^Function, n: ^Node) -> bool {
	fmt.println("test encode")
	return true
}

// because amd64 is just cool like that
DEBUG_ABI :: Amd64ABI.SysV64

amd64_get_callee_save_regmask :: proc(ctx: ^RegAllocContext) -> RegisterMask {
	return impl_amd64.abi[int(DEBUG_ABI)].callee_saved_regs
}

amd64_get_src_regmask :: proc(ctx: ^RegAllocContext, n: ^Node, from: int) -> RegisterMask {
	regmask := transmute(RegisterMask)insr_table[Amd64Insr(n.uop)].in_regmask
	uop := Amd64Insr(n.uop)
	#partial switch uop {
		case .Call:
			// FIXME: If you have too many integer arguments into the function the codegen backend for the lanuage might make some assumptions about the ABI instead of naively just spitting out types...
			// Double check on this because it would fuck up the counts maybe idk. the stack is the stack but still just check.
			param_node := n.inputs[from]
			param_mask_offset := from
			// There might be a better way to do this but it would require allocating memory or some shit i think, so come back and fix it if it matters at all ig...
			for i := from - 1; i > 2; i -= 1 {
				if !ty_equal(param_node.type, n.inputs[i].type) {
					param_mask_offset -= 1
				}
			}
			param_mask_offset -= 2 // transform to 0..n space to index the register mask out of the 2..n space for the parmeters
			if ty_is_int(param_node.type) {
				regmask = impl_amd64.abi[int(DEBUG_ABI)].int_param_regs[param_mask_offset]
			} else if ty_is_float(param_node.type) {
				regmask = impl_amd64.abi[int(DEBUG_ABI)].float_param_regs[param_mask_offset]
			}
			assert(regmask != 0)
		case .Ret:
			regmask = impl_amd64.abi[int(DEBUG_ABI)].return_regs // TODO: There's register splitting on SysV so just make sure all that bullshit works, idk...
	}
	assert(regmask != 0)
	return regmask
}

amd64_get_dst_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	table_ent := &insr_table[Amd64Insr(n.uop)]

	if amd64_is_two_address_op(ctx, n){
		two_addr_lrg := find_live_range(ctx, n.inputs[table_ent.two_address_index])
		return ctx.lrg_store[merge_live_range(ctx, two_addr_lrg, n)].available_mask
	}

	regmask := transmute(RegisterMask)table_ent.out_regmask
	uop := Amd64Insr(n.uop)
	#partial switch uop {
		case .Call:
			regmask = impl_amd64.abi[int(DEBUG_ABI)].return_regs
	}
	return regmask // some insrs are allowed to not produce any regs (Stores for example)
}

amd64_get_kill_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	return RegisterMask(0)
}

amd64_is_two_address_op :: proc(ctx: ^RegAllocContext, n: ^Node) -> bool {
	assert(n != nil)
	assert(n.uop != 0)
	return insr_table[Amd64Insr(n.uop)].two_address_index != 0
}

amd64_get_two_address_index :: proc(ctx: ^RegAllocContext, n: ^Node) -> int {
	assert(n != nil)
	assert(n.uop != 0)
	return insr_table[Amd64Insr(n.uop)].two_address_index
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
	for input in n.inputs[1:] {
		if !(ty_is_int(input.type) || ty_is_float(input.type)) {
			return false
		}
	}
	return true
}

amd64_imm_format :: proc(n: ^Node) -> bool {
	assert(len(n.inputs) == 3) // this only works for binops
	return (ty_is_int(n.inputs[1].type) || ty_is_float(n.inputs[1].type)) && is_const_node(n.inputs[2])
}

amd64_mem_format :: proc(n: ^Node) -> bool {
	assert(len(n.inputs) == 3) // this is only for binops
	return (ty_is_int(n.inputs[1].type) || ty_is_float(n.inputs[1].type)) && n.inputs[2].kind == .Load
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
	.CalleeSave = {},
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
	.Add = { { { insr = .AddMem, pred = amd64_mem_format }, { insr = .AddImm, pred = amd64_imm_format }, { insr = .Add, pred = amd64_reg_format } } },
	.Sub = { { { insr = .SubMem, pred = amd64_mem_format }, { insr = .SubImm, pred = amd64_imm_format }, { insr = .Sub, pred = amd64_reg_format } } },
	.Mul = { { { insr = .MulMem, pred = amd64_mem_format }, { insr = .MulImm, pred = amd64_imm_format }, { insr = .Mul, pred = amd64_reg_format } } },
	.Shl = { { { insr = .Shl, pred = amd64_reg_format }, { insr = .ShlImm, pred = amd64_imm_format } } },
	.Shr = { { { insr = .Shr, pred = amd64_reg_format }, { insr = .ShrImm, pred = amd64_imm_format } } },
	.Sar = { { { insr = .Sar, pred = amd64_reg_format }, { insr = .SarImm, pred = amd64_imm_format } } },
	.Rol = {},
	.Ror = {},
	.UDiv = { { { insr = .DivMem, pred = amd64_mem_format }, { insr = .DivImm, pred = amd64_imm_format }, { insr = .Div, pred = amd64_reg_format } } },
	.SDiv = { { { insr = .DivMem, pred = amd64_mem_format }, { insr = .DivImm, pred = amd64_imm_format }, { insr = .Div, pred = amd64_reg_format } } },
	.UMod = {},
	.SMod = {},
	.FAdd = { { { insr = .AddFMem, pred = amd64_mem_format }, { insr = .AddF, pred = amd64_reg_format } } },
	.FSub = { { { insr = .SubFMem, pred = amd64_mem_format }, { insr = .SubF, pred = amd64_reg_format } } },
	.FMul = { { { insr = .MulFMem, pred = amd64_mem_format }, { insr = .MulF, pred = amd64_reg_format } } },
	.FDiv = { { { insr = .DivFMem, pred = amd64_mem_format }, { insr = .DivF, pred = amd64_reg_format } } },
	.FMax = {},
	.FMin = {},
	.CmpEq = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpNeq = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpULt = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpULe = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpSLt = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpSLe = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpFLt = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.CmpFLe = { { { insr = .CmpMem, pred = amd64_mem_format }, { insr = .CmpImm, pred = amd64_imm_format }, { insr = .Cmp, pred = amd64_reg_format } } },
	.Not = {},
	.Negate = {},
}

InsrTableEntry :: struct {
	in_regmask:        Amd64RegMask,
	out_regmask:       Amd64RegMask,
	two_address_index: int,
}

insr_table := [Amd64Insr]InsrTableEntry {
	.Invalid = { },
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {} },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.Store = { in_regmask = GPR_READ_MASK, out_regmask = {} },
	.Add = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Sub = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SubImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SubMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Mul = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.MulImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.MulMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Div = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.DivImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.DivMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.AddFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.SubF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.SubFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.MulF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.MulFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.DivF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.DivFMem = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
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
	.CmpMem = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK },
}

Amd64Insr :: enum {
	Invalid,
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

