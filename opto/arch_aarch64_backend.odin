package opto

import "core:math/bits"
import "core:slice"

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
	select_new = aarch64_select_new,
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
	unimplemented("old function")
}

aarch64_select_new :: proc(fn: ^Function, n: ^Node) -> ^Node {
	switch n.kind {
	case .Start:
		return new_mach_node(fn, u32(AArch64Insr.Start), n)
	case .End:
		return clone_node(fn, n)
	case .Region:
		return clone_node(fn, n)
	case .Proj:
		return new_mach_node(fn, u32(AArch64Insr.Proj), n)
	case .IntConst:
		return new_mach_node(fn, u32(AArch64Insr.ConstStore), n)
	case .F32Const:
		return new_mach_node(fn, u32(AArch64Insr.ConstStore), n)
	case .F64Const:
		return new_mach_node(fn, u32(AArch64Insr.ConstStore), n)
	case .Local:
		return new_mach_node(fn, u32(AArch64Insr.Local), n)
	case .Symbol:
		return clone_node(fn, n)
	case .Param:
		return new_mach_node(fn, u32(AArch64Insr.Param), n)
	case .CalleeSave:
		return clone_node(fn, n)
	case .Return:
		return new_mach_node(fn, u32(AArch64Insr.Ret), n)
	case .Call:
		return new_mach_node(fn, u32(AArch64Insr.Call), n)
	case .Branch:
		return new_mach_node(fn, u32(AArch64Insr.Jmp), n)
	case .Goto:
		return new_mach_node(fn, u32(AArch64Insr.Jmp), n)
	case .Phi:
		return clone_node(fn, n)
	case .Load:
		return new_mach_node(fn, u32(AArch64Insr.Load), n)
	case .Store:
		return new_mach_node(fn, u32(AArch64Insr.Store), n)
	case .MemCpy:
		unimplemented("aarch64 memcpy")
	case .MemSet:
		unimplemented("aarch64 memset")
	case .VolatileRead:
		return new_mach_node(fn, u32(AArch64Insr.Load), n)
	case .VolatileWrite:
		return new_mach_node(fn, u32(AArch64Insr.Store), n)
	case .GetMemberPtr:
		unimplemented("aarch64 getmemberptr")
	case .And:
		return new_mach_node(fn, u32(AArch64Insr.And), n)
	case .Or:
		return new_mach_node(fn, u32(AArch64Insr.Or), n)
	case .XOr:
		return new_mach_node(fn, u32(AArch64Insr.XOr), n)
	case .Add:
		return new_mach_node(fn, u32(AArch64Insr.Add), n)
	case .Sub:
		return new_mach_node(fn, u32(AArch64Insr.Sub), n)
	case .Mul:
		return new_mach_node(fn, u32(AArch64Insr.Mul), n)
	case .Shl:
		return new_mach_node(fn, u32(AArch64Insr.Shl), n)
	case .Shr:
		return new_mach_node(fn, u32(AArch64Insr.Shr), n)
	case .Sar:
		return new_mach_node(fn, u32(AArch64Insr.Sar), n)
	case .Rol:
		return new_mach_node(fn, u32(AArch64Insr.Rol), n)
	case .Ror:
		return new_mach_node(fn, u32(AArch64Insr.Ror), n)
	case .UDiv:
		return new_mach_node(fn, u32(AArch64Insr.Div), n)
	case .SDiv:
		return new_mach_node(fn, u32(AArch64Insr.Div), n)
	case .UMod:
		return new_mach_node(fn, u32(AArch64Insr.Mod), n)
	case .SMod:
		return new_mach_node(fn, u32(AArch64Insr.Mod), n)
	case .FAdd:
		return new_mach_node(fn, u32(AArch64Insr.AddF), n)
	case .FSub:
		return new_mach_node(fn, u32(AArch64Insr.SubF), n)
	case .FMul:
		return new_mach_node(fn, u32(AArch64Insr.MulF), n)
	case .FDiv:
		return new_mach_node(fn, u32(AArch64Insr.DivF), n)
	case .FMax:
		return new_mach_node(fn, u32(AArch64Insr.MaxF), n)
	case .FMin:
		return new_mach_node(fn, u32(AArch64Insr.MinF), n)
	case .CmpEq:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpNeq:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpULt:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpULe:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpSLt:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpSLe:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpFLt:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .CmpFLe:
		return new_mach_node(fn, u32(AArch64Insr.Cmp), n)
	case .Not:
		return new_mach_node(fn, u32(AArch64Insr.Not), n)
	case .Negate:
		return new_mach_node(fn, u32(AArch64Insr.Neg), n)
	case .MachineOp:
		panic("got a machine op in isel")
	}
	panic("unhandled aarch64 instruction")
}

AARCH64_OP_LOAD_REG_64  :: 0b11111000011
AARCH64_OP_LOAD_REG_32  :: 0b10111000011
AARCH64_OP_LOAD_REG_16  :: 0b01111000010
AARCH64_OP_LOAD_REG_8   :: 0b00111000011
AARCH64_OP_LOAD_IMM_64  :: 0b1111100101
AARCH64_OP_LOAD_IMM_32  :: 0b1011100101
AARCH64_OP_LOAD_IMM_16  :: 0b0111100101
AARCH64_OP_LOAD_IMM_8   :: 0b0011100101
AARCH64_OP_STORE_REG_64 :: 0b11111000001
AARCH64_OP_STORE_REG_32 :: 0b10111000001
AARCH64_OP_STORE_REG_16 :: 0b01111000001
AARCH64_OP_STORE_REG_8  :: 0b00111000001
AARCH64_OP_STORE_IMM_64 :: 0b1111100100
AARCH64_OP_STORE_IMM_32 :: 0b1011100100
AARCH64_OP_STORE_IMM_16 :: 0b0111100100
AARCH64_OP_STORE_IMM_8  :: 0b0011100100
AARCH64_OP_MOVE_IMM8    :: 0b0
AARCH64_OP_MOVE_KEEP    :: 0b0
AARCH64_OP_MOVE_INV     :: 0b100100101
AARCH64_OP_MOVE_ZERO    :: 0b0
AARCH64_OP_MOVE_WIDE    :: 0b110100101
AARCH64_OP_ADD          :: 0b10001011
AARCH64_OP_ADD_IMM      :: 0b100100010
AARCH64_OP_SUB          :: 0b11001011
AARCH64_OP_SUB_IMM      :: 0b110100010
AARCH64_OP_MUL          :: 0b10011011000
AARCH64_OP_DIV          :: 0b10011010110
AARCH64_OP_CMP          :: 0b11101011
AARCH64_OP_CMP_IMM      :: 0b111100010
AARCH64_OP_JMP          :: 0b000101
AARCH64_OP_BR           :: 0b01010100
AARCH64_OP_CALL         :: 0b100101
AARCH64_OP_RET          :: 0b1101011001011111000000

enc_reg_reg :: proc(opcode: int, shift: int, rm: i128, imm6: int, rn: i128, rd: i128) -> u32 {
	assert(rm >= 0 && rm < 32)
	assert(rn >= 0 && rn < 32)
	assert(rd >= 0 && rd < 32)
	return u32(opcode << 24) | u32(shift << 21) | u32(rm << 16) | u32(imm6 << 10) | u32(rn << 5) | u32(rd)
}

enc_ret :: proc(opcode: int) -> u32 {
	return u32(opcode) << 10
}

aarch64_imm12 :: proc(imm: int) -> bool {
	return imm >= 0 && imm < (1 << 12)
}

aarch64_imm16 :: proc(imm: int) -> bool {
	return imm >= 0 && imm < (1 << 16)
}

enc_reg_imm :: proc(opcode: int, imm12: int, rn: int, rd: int) -> int {
	assert(rn >= 0 && rn < 32)
	assert(rd >= 0 && rd < 32)
	assert(aarch64_imm12(imm12))
	return (opcode << 23) | (imm12 << 10) | (rn << 5) | (rd)
}

StoreOption :: enum {
	UXTW = 0b010,
	LSL = 0b011,
	SXTW = 0b110,
	SXTX = 0b111,
}

enc_ldstr :: proc(opcode: int, offset: int, option: StoreOption, shift: int, val: int, ptr: int) -> int {
	assert(val >= 0 && val <= 32)
	assert(ptr >= 0 && ptr <= 32)
	assert(shift >= 0 && shift <= 1)
	return (opcode << 21) | (offset << 16) | (int(option) << 13) | (shift << 12) | (2 << 10) | (ptr << 5) | (val)
}

enc_ldstr_imm :: proc(opcode: int, imm12: int, ptr: int, rt: int) -> int {
	assert(ptr >= 0 && ptr <= 32)
	assert(rt >= 0 && rt <= 32)
	assert(aarch64_imm12(imm12))
	return (opcode << 22) | (imm12 << 10) | (ptr << 5) | (rt)
}

enc_madd :: proc(opcode: int, rm: int, ra: int, rn: int, rd: int) -> u32 {
	assert(rm >= 0 && rm <= 32)
	assert(rn >= 0 && rn <= 32)
	assert(rn >= 0 && rn <= 32)
	return u32(opcode << 21) | u32(rm << 16) | u32(ra << 10) | u32(rn << 5) | u32(rd)
}

aarch64_regname :: proc(reg: i128) -> string {
	assert(reg < i128(AArch64Reg.MAX_REG))
	return impl_aarch64.reg_names[reg]
}

aarch64_encode :: proc(fn: ^Function, n: ^Node, bm: ^BlockMap) -> bool {
	uop := AArch64Insr(n.uop)
	switch uop {
		case .Invalid:
		case .Imm:
		case .Start:
			if fn.stack_size > 0 {
				insr := enc_reg_imm(AARCH64_OP_SUB_IMM, fn.stack_size, int(AArch64Reg.SP), int(AArch64Reg.SP))
				enc_out32(&fn.output.data, insr)
				log(fn, "    sub.x sp, sp, #{}", fn.stack_size)
			}
		case .Param:
		case .Proj:
		case .Local:
		case .Ret:
			if fn.stack_size > 0 {
				enc_out32(&fn.output.data, enc_reg_imm(AARCH64_OP_ADD_IMM, fn.stack_size, int(AArch64Reg.SP), int(AArch64Reg.SP)))
				log(fn, "    add.x sp, sp, #{}", fn.stack_size)
			}
			enc_out32(&fn.output.data, int(enc_ret(AARCH64_OP_RET)))
			log(fn, "    ret")
		case .Call:
			target := n.inputs[2]
			target_sym := target.extra.derived.(^SymbolExtra).sym
			add_global_relo(fn, n, nil)
			insr := u32(AARCH64_OP_CALL << 26)
			enc_out32(&fn.output.data, int(insr))
			log(fn, "    bl {}", target_sym.name)
		case .Jmp:
			target: ^Node
			if n.kind == .Branch {
				target = n.inputs[2]
				bb := block_map_get_node_block(bm, target)
				opcode := AARCH64_OP_BR
				off19 := 0
				cond, cond_str := aarch64_cond(n.inputs[1].kind)
				insr := (opcode << 24) | (off19 << 5) | (1 << 4) | int(cond)
				log(fn, "    b.{} {}", cond_str, bb.name)
				enc_out32(&fn.output.data, insr)
			} else {
				assert(n.kind == .Goto)
				target = n.inputs[1]
				bb := block_map_get_node_block(bm, target)
				opcode := AARCH64_OP_JMP
				off := 0
				insr := u32(opcode << 26) | u32(off)
				log(fn, "    b {}", bb.name)
				enc_out32(&fn.output.data, int(insr))
			}
			add_local_relo(fn, n, target)
		case .Load:
			dst_reg := get_reg(fn, n)
			assert(dst_reg < i128(AArch64Reg.MAX_REG))
			ptr_reg := get_reg(fn, n.inputs[2])
			offset := 0
			if ptr_reg >= i128(AArch64Reg.MAX_REG) {
				ptr_reg = i128(AArch64Reg.SP)
				offset = get_local_slot_offset(fn, n.inputs[2])
			}

			insr: int
			bw := n.type.bitwidth
			if offset != 0 {
				opcode := -1
				if bw <= 8 {
					opcode = AARCH64_OP_LOAD_IMM_8
					log(fn, "    ldr.b {}, [{}, #{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg), offset)
				} else if bw <= 16 {
					opcode = AARCH64_OP_LOAD_IMM_16
					log(fn, "    ldr.h {}, [{}, #{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg), offset)
				} else if bw <= 32 {
					opcode = AARCH64_OP_LOAD_IMM_32
					log(fn, "    ldr.w {}, [{}, #{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg), offset)
				} else {
					assert(bw <= 64)
					opcode = AARCH64_OP_LOAD_IMM_64
					log(fn, "    ldr.x {}, [{}, #{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg), offset)
				}
				insr = enc_ldstr_imm(opcode, offset, int(ptr_reg), int(dst_reg))
			} else {
				opcode := -1
				if bw <= 8 {
					opcode = AARCH64_OP_LOAD_IMM_8
					log(fn, "    ldr.b {}, [{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg))
				} else if bw <= 16 {
					opcode = AARCH64_OP_LOAD_IMM_16
					log(fn, "    ldr.h {}, [{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg))
				} else if bw <= 32 {
					opcode = AARCH64_OP_LOAD_IMM_32
					log(fn, "    ldr.w {}, [{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg))
				} else {
					assert(bw <= 64)
					opcode = AARCH64_OP_LOAD_IMM_64
					log(fn, "    ldr.x {}, [{}]", aarch64_regname(dst_reg), aarch64_regname(ptr_reg))
				}
				insr = enc_ldstr_imm(opcode, 0, int(ptr_reg), int(dst_reg))
			}
			enc_out32(&fn.output.data, insr)
		case .GetMemberPtr:
			// panic("impl getmemberptr")
		case .ConstStore:
			assert(is_const_node(n))
			imm := get_imm_int(n)
			dst_reg := get_reg(fn, n)
			bw := n.type.bitwidth
			opcode := AARCH64_OP_MOVE_WIDE
			mov_type := "w"
			hw := 0

			if imm < 0 {
				opcode = AARCH64_OP_MOVE_INV
				mov_type = "i"
				imm = ~imm
			}

			assert(aarch64_imm16(imm))

			insr := (opcode << 23) | (hw << 21) | (imm << 5) | int(dst_reg)
			log(fn, "    mov.{} {}, #{}", mov_type, aarch64_regname(dst_reg), imm)

			enc_out32(&fn.output.data, insr)
		case .Store:
			offset := 0
			ptr_reg := get_reg(fn, n.inputs[2])
			if ptr_reg >= i128(AArch64Reg.MAX_REG) {
				ptr_reg = i128(AArch64Reg.SP)
				offset = get_local_slot_offset(fn, n.inputs[2])
			}
			val_reg := get_reg(fn, n.inputs[3])
			assert(val_reg < i128(AArch64Reg.MAX_REG))
			opcode: int
			insr: int
			bw := n.inputs[3].type.bitwidth
			if offset != 0 {
				if bw <= 8 {
					opcode = AARCH64_OP_STORE_IMM_8
					log(fn, "    str.b {}, [{}, #{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg), offset)
				} else if bw <= 16 {
					opcode = AARCH64_OP_STORE_IMM_16
					log(fn, "    str.h {}, [{}, #{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg), offset)
				} else if bw <= 32 {
					opcode = AARCH64_OP_STORE_IMM_32
					log(fn, "    str.w {}, [{}, #{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg), offset)
				} else {
					assert(bw <= 64)
					opcode = AARCH64_OP_STORE_IMM_64
					log(fn, "    str.x {}, [{}, #{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg), offset)
				}
				insr = enc_ldstr_imm(opcode, offset, int(ptr_reg), int(val_reg))
			} else {
				if bw <= 8 {
					opcode = AARCH64_OP_STORE_IMM_8
					log(fn, "    str.b {}, [{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg))
				} else if bw <= 16 {
					opcode = AARCH64_OP_STORE_IMM_16
					log(fn, "    str.h {}, [{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg))
				} else if bw <= 32 {
					opcode = AARCH64_OP_STORE_IMM_32
					log(fn, "    str.w {}, [{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg))
				} else {
					assert(bw <= 64)
					opcode = AARCH64_OP_STORE_IMM_64
					log(fn, "    str.x {}, [{}]", aarch64_regname(val_reg), aarch64_regname(ptr_reg))
				}
				insr = enc_ldstr_imm(opcode, 0, int(ptr_reg), int(val_reg))
			}
			enc_out32(&fn.output.data, insr)
		case .Add:
			panic("impl add")
		case .AddImm:
			panic("impl addi")
		case .Sub:
			panic("impl sub")
		case .SubImm:
			dst_reg := get_reg(fn, n)
			assert(dst_reg >= 0 && dst_reg <= 32)
			v_reg := get_reg(fn, n.inputs[1])
			assert(v_reg >= 0 && v_reg <= 32)
			assert(is_const_node(n.inputs[2]))
			imm := get_imm_int(n.inputs[2])
			opcode := AARCH64_OP_SUB_IMM
			insr := enc_reg_imm(opcode, imm, int(v_reg), int(dst_reg))
			enc_out32(&fn.output.data, insr)
		case .Mul:
			dst_reg := get_reg(fn, n)
			l_reg := get_reg(fn, n.inputs[1])
			r_reg := get_reg(fn, n.inputs[2])
			insr := enc_madd(AARCH64_OP_MUL, int(r_reg), 0b11111, int(l_reg), int(dst_reg))
			log(fn, "    mul {}, {}, {}", aarch64_regname(dst_reg), aarch64_regname(l_reg), aarch64_regname(r_reg))
			enc_out32(&fn.output.data, int(insr))
		case .Div:
			panic("impl div")
		case .DivImm:
			panic("impl divi")
		case .Mod:
			panic("impl mod")
		case .AddF:
			panic("impl addf")
		case .SubF:
			panic("impl subf")
		case .MulF:
			panic("impl mulf")
		case .DivF:
			panic("impl divf")
		case .MaxF:
			panic("impl maxf")
		case .MinF:
			panic("impl minf")
		case .Sal:
			panic("impl sal")
		case .SalImm:
			panic("impl sali")
		case .Sar:
			panic("impl sar")
		case .SarImm:
			panic("impl sari")
		case .Rol:
			panic("impl rol")
		case .Ror:
			panic("impl ror")
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
			opcode := AARCH64_OP_CMP
			sh := 0
			l_reg := get_reg(fn, n.inputs[1])
			assert(l_reg >= 0 && l_reg <= 32)
			r_reg := get_reg(fn, n.inputs[2])
			assert(r_reg >= 0 && r_reg <= 32)
			imm6 := 0
			insr := u32(opcode << 24) | u32(sh << 22) | u32(r_reg << 16) | u32(imm6 << 10) | u32(l_reg << 5) | u32(0b11111)
			log(fn, "    cmp {}, {}", aarch64_regname(l_reg), aarch64_regname(r_reg))
			enc_out32(&fn.output.data, int(insr))
		case .CmpImm:
			opcode := AARCH64_OP_CMP_IMM
			sh := 0
			arg_reg := get_reg(fn, n.inputs[1])
			assert(arg_reg >= 0 && arg_reg <= 32)
			assert(is_const_node(n.inputs[2]))
			imm := get_imm_int(n.inputs[2])
			assert(aarch64_imm12(imm))
			insr := u32(opcode << 23) | u32(sh << 22) | u32(imm << 10) | (u32(arg_reg) << 5) | u32(0b11111)
			log(fn, "    cmpi {}, #{}", aarch64_regname(arg_reg), imm)
			enc_out32(&fn.output.data, int(insr))
		case .Not:
			panic("impl not")
		case .Neg:
			panic("impl neg")
	}
	return true
}

AArch64Cond :: enum(u32) {
	EQ = 0b0000,
	NE = 0b0001,
	CC = 0b0011,
	LS = 0b1001,
	LT = 0b1011,
	LE = 0b1101,
}
aarch64_cond :: proc(cmp: NodeKind) -> (AArch64Cond, string) {
	cond: AArch64Cond
	str := ""
	#partial switch cmp {
	case .CmpEq:
		cond = .EQ
		str = "eq"
	case .CmpNeq:
		cond = .NE
		str = "ne"
	case .CmpULt:
		cond = .CC
		str = "lo"
	case .CmpULe:
		cond = .LS
		str = "ls"
	case .CmpSLt:
		cond = .LT
		str = "lt"
	case .CmpSLe:
		cond = .LE
		str = "le"
	case .CmpFLt:
		cond = .LT
		str = "lt"
	case .CmpFLe:
		cond = .LE
		str = "le"
	case:
		panic("cmp node has non cmp kind")
	}
	return cond, str
}

@(private = "file")
get_local_slot_offset :: proc(fn: ^Function, local: ^Node) -> int {
	extra := local.extra.derived.(^LocalExtra)
	return fn.stack_size + extra.stack_pos
}

aarch64_encoding_size :: proc(n: ^Node, delta_from_start_to_target: int) -> int {
	return 4 // arm has a regular insr encoding
}

aarch64_patch_local_relo :: proc(fn: ^Function, n: ^Node, start: int, delta_from_start_to_target: int) {
	uop := AArch64Insr(n.uop)
	rel_addr :: proc(off: int, bw: uint) -> int {
		assert(off >= -(1 << bw) && off < 1 << bw)
		ret := off
		assert(ret & 0b11 == 0)
		ret >>= 2
		return ret & ((1 << bw) - 1)
	}
	#partial switch uop {
	case .Jmp:
		new_insr: u32
		if n.kind == .Branch {
			opcode := AARCH64_OP_BR
			off19 := rel_addr(delta_from_start_to_target, 19)
			cond, _ := aarch64_cond(n.inputs[1].kind)
			new_insr = u32(opcode << 24) | u32(off19 << 5) | u32(cond)
		} else {
			assert(n.kind == .Goto)
			opcode := AARCH64_OP_JMP
			off := rel_addr(delta_from_start_to_target, 26)
			new_insr = u32(opcode << 26) | u32(off)
		}
		patch_insr(fn.output.data[:], start, new_insr)
	case .Call:
		opcode := AARCH64_OP_CALL
		off := rel_addr(delta_from_start_to_target, 26)
		new_insr := u32(opcode << 26) | u32(off)
		patch_insr(fn.output.data[:], start, new_insr)
	case:
		panic("unexpected patch node")
	}

	patch_insr :: proc(to: []u8, at: int, insr: u32) {
		new := insr
		new_slice := slice.bytes_from_ptr(&new, size_of(new))
		copy(to[at:at+4], new_slice)
	}
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

aarch64_is_imm_store :: proc(n: ^Node) -> bool {
	for user in n.users {
		if user.n.kind == .Store || user.n.kind == .Mul || is_cmp_node(user.n) do return true
	}
	return false
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
	.Imm = { },
	.Start = { in_regmask = {}, out_regmask = {} },
	.Param = { in_regmask = {}, out_regmask = {} },
	.Proj = { in_regmask = {}, out_regmask = {} },
	.Local = { in_regmask = {}, out_regmask = transmute(AArch64RegMask)SPILL_MASK },
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {} },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.GetMemberPtr = { in_regmask = GPR_READ_MASK | transmute(AArch64RegMask)SPILL_MASK, out_regmask = GPR_WRITE_MASK },
	.ConstStore = { in_regmask = {}, out_regmask = GPR_WRITE_MASK },
	.Store = { in_regmask = GPR_READ_MASK, out_regmask = {} },
	.Add = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.AddImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Sub = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SubImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Mul = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Div = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.DivImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Mod = { },
	.AddF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.SubF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.MulF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.DivF = { in_regmask = XMM_MASK, out_regmask = XMM_MASK, two_address_index = 1 },
	.MaxF = { },
	.MinF = { },
	.Sal = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SalImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Sar = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.SarImm = { in_regmask = GPR_WRITE_MASK, out_regmask = GPR_WRITE_MASK, two_address_index = 1 },
	.Rol = { },
	.Ror = { },
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
	.Not = { },
	.Neg = { },
}

AArch64Insr :: enum(u32) {
	Invalid,
	Imm,
	Start,
	Param,
	Proj,
	Local,
	Ret,
	Call,
	Jmp,
	Load,
	GetMemberPtr,
	ConstStore,
	Store,
	Add,
	AddImm,
	Sub,
	SubImm,
	Mul,
	Div,
	DivImm,
	Mod,
	AddF,
	SubF,
	MulF,
	DivF,
	MaxF,
	MinF,
	Sal,
	SalImm,
	Sar,
	SarImm,
	Rol,
	Ror,
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
	Not,
	Neg,
}
