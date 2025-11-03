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

amd64_select :: proc(fn: ^Function, n: ^Node) -> MachineOp {
	fmt.println("test select")
	return INVALID_OP
}

amd64_encode :: proc(fn: ^Function, n: ^Node) -> bool {
	fmt.println("test encode")
	return true
}


MachineNode :: struct {
}

InsrTableEntry :: struct {
	in_regmask:  Amd64RegMask,
	out_regmask: Amd64RegMask,
	encode:      #type proc(m: ^MachineNode) -> bool,
}

ret_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

call_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

jmp_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

load_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

store_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

add_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

sub_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

mul_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

shl_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

shr_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

or_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

xor_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

cmp_encode :: proc(m: ^MachineNode) -> bool {
	return true
}

insr_table := [Amd64Insr]InsrTableEntry {
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {}, encode = ret_encode },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {}, encode = call_encode },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {}, encode = jmp_encode },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = load_encode },
	.Store = { in_regmask = GPR_READ_MASK, out_regmask = {}, encode = store_encode },
	.Add = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = add_encode },
	.AddImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = add_encode },
	.AddMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = add_encode },
	.Sub = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = sub_encode },
	.SubImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = sub_encode },
	.SubMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = sub_encode },
	.Mul = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = mul_encode },
	.MulImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = mul_encode },
	.MulMem = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = mul_encode },
	.Shl = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = shl_encode },
	.ShlImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = shl_encode },
	.Shr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = shr_encode },
	.ShrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = shr_encode },
	.Or = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = or_encode },
	.OrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = or_encode },
	.XOr = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, encode = xor_encode },
	.XOrImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, encode = xor_encode },
	.Cmp = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK, encode = cmp_encode },
	.CmpImm = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK, encode = cmp_encode },
	.CmpMem = { in_regmask = GPR_READ_MASK, out_regmask = FLAGS_MASK, encode = cmp_encode },
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
	Shl,
	ShlImm,
	Shr,
	ShrImm,
	Or,
	OrImm,
	XOr,
	XOrImm,
	Cmp,
	CmpImm,
	CmpMem,
}

