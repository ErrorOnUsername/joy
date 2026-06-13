package opto

import "core:fmt"


Amd64Reg :: enum(RegisterID) {
	RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15,
	XMM0, XMM1, XMM2, XMM3, XMM4, XMM5, XMM6, XMM7, XMM8, XMM9, XMM10, XMM11, XMM12, XMM13, XMM14, XMM15,
	RFLAGS,
	MAX_REG,
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
@(private = "file")
SPILL_MASK := RegisterMask(-int(1 << uint(Amd64Reg.MAX_REG)))

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
	encoding_size = amd64_encoding_size,
	patch_local_relo = amd64_patch_local_relo,
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
	out := &fn.output.data
	uop := Amd64Insr(n.uop)
	switch uop {
	case .Invalid:
		panic("invalid amd64 instruction")
	case .Proj:
	case .Local:
	case .Ret:
		// we just always use near returns
		// FIXME: are far returns even needed ever since segments aren't really used in long mode?
		append(out, 0xC3)
	case .Call:
		append(out, 0xE8)
		append(out, 0, 0, 0, 0)
		add_global_relo(fn, n, nil)
	case .Jmp:
		if n.kind == .Branch {
			jump_op := amd64_get_br_jump_op(n, 8)
			append(out, jump_op, 0)
		} else {
			assert(n.kind == .Goto)
			append(out, 0xEB, 0) // this gets patched to the other forms for larger disps
		}
	case .Load:
		bw := 0
		is_fp := false
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case .Float:
				is_fp = true
				bw = int(n.type.bitwidth)
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n)
		assert(dst_reg < int(Amd64Reg.MAX_REG))


		index_reg := -1
		offset := 0
		scale := 0

		ptr_reg := get_reg(fn, n.inputs[2])
		if ptr_reg >= int(Amd64Reg.MAX_REG) {
			offset = get_local_slot_offset(fn, n.inputs[2])
			ptr_reg = int(Amd64Reg.RSP)
		}

		if !is_fp {
			if bw <= 8 {
				append(out, 0x8A) // 8A /r MOV r8, r/m8
			} else if bw <= 16 {
				append(out, 0x66, 0x8B) // 8B /r MOV r16, r/m16
			} else if bw <= 32 {
				append(out, 0x8B) // 8B /r MOV r32, r/m32
			} else {
				assert(bw <= 64)
				rex := rex_prefix(dst_reg, ptr_reg, index_reg, true)
				append(out, rex, 0x8B) // REX.W + 8B /r MOV r64, r/m64
			}
		} else {
			if bw == 32 {
				append(out, 0xF3, 0x0F, 0x10) // F3 0F 10 /r MOVSS xmm1, m32
			} else {
				assert(bw == 64)
				append(out, 0xF2, 0x0F, 0x10) // F2 0F 10 /r MOVSD xmm1, m64
			}
		}

		amd64_indirect_load(out, dst_reg, ptr_reg, index_reg, offset, scale)
	case .GetMemberPtr:
		dst_reg := get_reg(fn, n)
		assert(dst_reg < int(Amd64Reg.MAX_REG))

		index_reg := -1
		offset := 0
		scale := 0

		src_reg := get_reg(fn, n.inputs[1])
		if src_reg >= int(Amd64Reg.MAX_REG) {
			offset = get_local_slot_offset(fn, n.inputs[1])
			src_reg = int(Amd64Reg.RSP)
		}

		member_off := get_imm_int(n.inputs[2])
		offset += member_off

		rex := rex_prefix(dst_reg, src_reg, index_reg, true)
		append(out, rex, 0x8D)

		amd64_indirect_load(out, dst_reg, src_reg, index_reg, offset, scale)
	case .Store:
		bw := 0
		is_fp := false
		val := n.inputs[3]
		#partial switch val.type.kind {
			case .Int:
				bw = int(val.type.bitwidth)
			case .Ptr:
				bw = 64
			case .Float:
				is_fp = true
				bw = int(val.type.bitwidth)
			case:
				panic("bad store type")
		}

		index_reg := -1
		offset := 0
		scale := 0

		ptr_reg := get_reg(fn, n.inputs[2])
		if ptr_reg >= int(Amd64Reg.MAX_REG) {
			offset = get_local_slot_offset(fn, n.inputs[2])
			ptr_reg = int(Amd64Reg.RSP)
		}

		if is_const_node(val) {
			if !is_fp {
				if bw <= 8 {
					append(out, 0xC6) // C6 /0 ib	MOV r/m8, imm8
				} else if bw <= 16 {
					append(out, 0x66, 0xC7) // C7 /0 iw	MOV r/m16, imm16
				} else if bw <= 32 {
					append(out, 0xC7) // C7 /0 id	MOV r/m32, imm32
				} else {
					assert(bw <= 64)
					rex := rex_prefix(-1, ptr_reg, index_reg, true)
					append(out, rex, 0xC7) // REX.W + C7 /0 id	MOV r/m64, imm32
				}
				amd64_indirect_load(out, -1, ptr_reg, index_reg, offset, scale)
				imm := get_imm_int(val)
				if bw <= 8 {
					enc_out8(out, imm)
				} else if bw <= 16 {
					enc_out16(out, imm)
				} else {
					enc_out32(out, imm)
				}
			} else {
				panic("float imm store")
			}
		} else {
			val_reg := get_reg(fn, val)
			assert(val_reg < int(Amd64Reg.MAX_REG))

			if !is_fp {
				if bw <= 8 {
					append(out, 0x88) // 88 /r MOV r/m8, r8
				} else if bw <= 16 {
					append(out, 0x66, 0x89) // 89 /r MOV r/m16, r16
				} else if bw <= 32 {
					append(out, 0x89) // 89 /r MOV r/m32, r32
				} else {
					assert(bw <= 64)
					rex := rex_prefix(val_reg, ptr_reg, index_reg, true)
					append(out, rex, 0x89) // REX.W + 89 /r MOV r/m64, r64
				}
			} else {
				panic("float store")
			}
			amd64_indirect_load(out, ptr_reg, val_reg, index_reg, offset, scale)
		}
	case .Add:
		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		src_reg := get_reg(fn, n.inputs[2])
		rex := rex_prefix(dst_reg, src_reg, 0, true)

		prefix: u8 = 0xFF
		opcode: u8 = 0xFF
		assert(n.type.kind == .Int || n.type.kind == .Ptr)
		if n.type.kind == .Int {
			if n.type.bitwidth <= 8 {
				opcode = 0x02
			} else if n.type.bitwidth <= 16 {
				prefix = 0x66
				opcode = 0x03
			} else if n.type.bitwidth <= 32 {
				opcode = 0x03
			} else if n.type.bitwidth <= 64 {
				prefix = rex
				opcode = 0x03
			}
		} else if n.type.kind == .Ptr {
			prefix = rex
			opcode = 0x03 // just a 64-bit add
		} else {
			panic("bad type on reg add")
		}
		assert(opcode != 0xFF)
		modrm := modrm_byte(.Direct, dst_reg, src_reg)
		if prefix != 0xFF {
			append(out, prefix, opcode, modrm)
		} else {
			append(out, opcode, modrm)
		}
	case .AddImm:
		bw := 0
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		imm := get_imm_int(n.inputs[2])

		modrm := modrm_byte(.Direct, 0, dst_reg)
		if bw <= 8 {
			append(out, 0x80, modrm)
			enc_out8(out, imm)
		} else if bw <= 16 {
			if amd64_is_imm8(imm) {
				append(out, 0x66, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x66, 0x81, modrm)
				enc_out16(out, imm)
			}
		} else if bw <= 32 {
			if amd64_is_imm8(imm) {
				append(out, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x81, modrm)
				enc_out16(out, imm)
			}
		} else {
			assert(bw <= 64)
			rex := rex_prefix(0, dst_reg, 0, true)
			if amd64_is_imm8(imm) {
				append(out, rex, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, rex, 0x81, modrm)
				enc_out16(out, imm)
			}
		}
	case .AddMem:
		panic("addmem")
	case .Sub:
		bw := 0
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		src_reg := get_reg(fn, n.inputs[2])

		modrm := modrm_byte(.Direct, dst_reg, src_reg)
		if bw <= 8 {
			append(out, 0x2A, modrm)
		} else if bw <= 16 {
			append(out, 0x66, 0x2B, modrm)
		} else if bw <= 32 {
			append(out, 0x2B, modrm)
		} else {
			assert(bw <= 64)
			rex := rex_prefix(dst_reg, src_reg, 0, true)
			append(out, rex, 0x2B, modrm)
		}
	case .SubImm:
		bw := 0
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		imm := get_imm_int(n.inputs[2])
		modrm := modrm_byte(.Direct, 5, dst_reg)

		if bw <= 8 {
			append(out, 0x80, modrm)
			enc_out8(out, imm)
		} else if bw <= 16 {
			if amd64_is_imm8(imm) {
				append(out, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x81, modrm)
				enc_out16(out, imm)
			}
		} else if bw <= 32 {
			if amd64_is_imm8(imm) {
				append(out, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x81, modrm)
				enc_out32(out, imm)
			}
		} else {
			rex := rex_prefix(0, dst_reg, 0, true)
			if amd64_is_imm8(imm) {
				append(out, rex, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, rex, 0x81, modrm)
				enc_out32(out, imm)
			}
		}
	case .SubMem:
		panic("sub mem")
	case .Mul:
		bw := 0
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		src_reg := get_reg(fn, n.inputs[2])
		modrm := modrm_byte(.Direct, dst_reg, src_reg)

		if bw <= 8 {
			panic("this can only target %al, so we gotta fix that shit")
		} else if bw <= 16 {
			append(out, 0x66, 0x0F, 0xAF, modrm)
		} else if bw <= 32 {
			append(out, 0x0F, 0xAF, modrm)
		} else {
			assert(bw <= 64)
			rex := rex_prefix(dst_reg, src_reg, 0, true)
			append(out, rex, 0x0F, 0xAF, modrm)
		}
	case .MulImm:
		bw := 0
		#partial switch n.type.kind {
			case .Int:
				bw = int(n.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, n.inputs[1]) // two addr
		imm := get_imm_int(n.inputs[2])
		modrm := modrm_byte(.Direct, dst_reg, dst_reg)

		if bw <= 8 {
			panic("mulimm on single byte")
		} else if bw <= 16 {
			if amd64_is_imm8(imm) {
				append(out, 0x66, 0x69, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x66, 0x6B, modrm)
				enc_out16(out, imm)
			}
		} else if bw <= 32 {
			if amd64_is_imm8(imm) {
				append(out, 0x69, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x6B, modrm)
				enc_out32(out, imm)
			}
		} else {
			assert(bw <= 64)
			rex := rex_prefix(dst_reg, dst_reg, 0, true)
			if amd64_is_imm8(imm) {
				append(out, rex, 0x69, modrm)
				enc_out8(out, imm)
			} else {
				append(out, rex, 0x6B, modrm)
				enc_out32(out, imm)
			}
		}
	case .MulMem:
		dst_reg := get_reg(fn, n.inputs[1])
		assert(dst_reg < int(Amd64Reg.MAX_REG))
		src_reg := get_reg(fn, n.inputs[2])
		if src_reg >= int(Amd64Reg.MAX_REG) {
			src_reg = int(Amd64Reg.RSP)
		}

		bw := n.type.bitwidth
		if n.type.kind == .Ptr {
			bw = 64
		}

		if bw <= 8 {
			panic("byte multiply idk fix it")
		} else if bw <= 16 {
			append(out, 0x66, 0x0F, 0xAF) // 0F AF /r IMUL r16, r/m16
		} else if bw <= 32 {
			append(out, 0x0F, 0xAF) // 0F AF /r IMUL r32, r/m32
		} else if bw <= 64 {
			rex := rex_prefix(dst_reg, src_reg, 0, true)
			append(out, rex, 0x0F, 0xAF) // REX.W + 0F AF /r IMUL r32, r/m32
		}

		scale := 0
		offset := 0
		if n.inputs[2].kind == .Local {
			offset = get_local_slot_offset(fn, n.inputs[2])
		}
		amd64_indirect_load(out, dst_reg, src_reg, -1, offset, scale)
	case .Div:
		panic("div")
	case .DivImm:
		panic("div imm")
	case .DivMem:
		panic("div mem")
	case .AddF:
		panic("addf")
	case .AddFMem:
		panic("addf mem")
	case .SubF:
		panic("subf")
	case .SubFMem:
		panic("subf mem")
	case .MulF:
		panic("mulf")
	case .MulFMem:
		panic("mulf mem")
	case .DivF:
		panic("divf")
	case .DivFMem:
		panic("divf mem")
	case .Sal:
		panic("sal")
	case .SalImm:
		panic("sal imm")
	case .Sar:
		panic("sar")
	case .SarImm:
		panic("sar imm")
	case .Shl:
		panic("shl")
	case .ShlImm:
		panic("shl imm")
	case .Shr:
		panic("shr")
	case .ShrImm:
		panic("shr imm")
	case .And:
		panic("and")
	case .AndImm:
		panic("and imm")
	case .Or:
		panic("or")
	case .OrImm:
		panic("or imm")
	case .XOr:
		panic("xor")
	case .XOrImm:
		panic("xor imm")
	case .Cmp:
		panic("cmp")
	case .CmpImm:
		bw := 0
		in_val := n.inputs[1]
		#partial switch in_val.type.kind {
			case .Int:
				bw = int(in_val.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		dst_reg := get_reg(fn, in_val) // two addr
		imm := get_imm_int(n.inputs[2])
		modrm := modrm_byte(.Direct, 7, dst_reg)

		if bw <= 8 {
			append(out, 0x80, modrm)
			enc_out8(out, imm)
		} else if bw <= 16 {
			if amd64_is_imm8(imm) {
				append(out, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x81, modrm)
				enc_out16(out, imm)
			}
		} else if bw <= 32 {
			if amd64_is_imm8(imm) {
				append(out, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, 0x81, modrm)
				enc_out32(out, imm)
			}
		} else {
			rex := rex_prefix(0, dst_reg, 0, true)
			if amd64_is_imm8(imm) {
				append(out, rex, 0x83, modrm)
				enc_out8(out, imm)
			} else {
				append(out, rex, 0x81, modrm)
				enc_out32(out, imm)
			}
		}
	case .CmpMem:
		bw := 0
		in_val := n.inputs[1]
		#partial switch in_val.type.kind {
			case .Int:
				bw = int(in_val.type.bitwidth)
			case .Ptr:
				bw = 64
			case:
				panic("bad load type")
		}

		index_reg := -1
		offset := 0
		scale := 0

		ptr_reg := get_reg(fn, n.inputs[2])
		if ptr_reg >= int(Amd64Reg.MAX_REG) {
			offset = get_local_slot_offset(fn, n.inputs[2])
			ptr_reg = int(Amd64Reg.RSP)
		}

		if is_const_node(in_val) {
			imm := get_imm_int(in_val)
			fits_in_single_byte := amd64_is_imm8(imm)
			opcode_bump: u8 = 2 if fits_in_single_byte else 0

			if bw <= 8 {
				append(out, 0x80)
			} else if bw <= 16 {
				append(out, 0x66, 0x81 + opcode_bump)
			} else if bw <= 32 {
				append(out, 0x81 + opcode_bump)
			} else {
				assert(bw <= 64)
				rex := rex_prefix(-1, ptr_reg, 0, true)
				append(out, rex, 0x81 + opcode_bump)
			}

			amd64_indirect_load(out, 7, ptr_reg, index_reg, offset, scale)

			if bw <= 8 || fits_in_single_byte {
				enc_out8(out, imm)
			} else if bw <= 16 {
				enc_out16(out, imm)
			} else if bw <= 32 {
				enc_out32(out, imm)
			} else {
				assert(bw <= 64)
				enc_out32(out, imm)
			}
		} else {
			val_reg := get_reg(fn, in_val)
			assert(val_reg < int(Amd64Reg.MAX_REG))

			if bw <= 8 {
				append(out, 0x38)
			} else if bw <= 16 {
				append(out, 0x66, 0x39)
			} else if bw <= 32 {
				append(out, 0x39)
			} else {
				assert(bw <= 64)
				rex := rex_prefix(val_reg, ptr_reg, 0, true)
				append(out, rex, 0x39)
			}
			amd64_indirect_load(out, val_reg, ptr_reg, index_reg, offset, scale)
		}
	}
	return true
}

get_local_slot_offset :: proc(fn: ^Function, local: ^Node) -> int {
	extra := local.extra.derived.(^LocalExtra)
	return extra.stack_pos - fn.stack_size
}

amd64_is_imm8 :: proc(imm: int) -> bool {
	data := transmute(uint)imm
	return data <= 0xFF
}

amd64_indirect_load :: proc(out: ^[dynamic]u8, dst_reg: int, ptr_reg: int, index_reg: int, offset: int, scale: int) {
	mod := MODAddressingMode.Indirect
	if offset != 0 {
		mod = .IndirectDisp8 if amd64_is_imm8(offset) else .IndirectDisp32
	}

	if index_reg == -1 {
		append(out, modrm_byte(mod, dst_reg, ptr_reg))
	} else {
		append(out, modrm_byte(mod, dst_reg, int(Amd64Reg.RSP)))
		append(out, sib_byte(scale, index_reg, ptr_reg))
	}

	if mod == .IndirectDisp8 {
		enc_out8(out, offset)
	} else if mod == .IndirectDisp32 {
		enc_out32(out, offset)
	}
}

amd64_get_br_jump_op :: proc(n: ^Node, rel_size: u8) -> u8 {
	assert(rel_size == 8 || rel_size == 32)
	assert(n.kind == .Branch)
	cond := n.inputs[1]
	op: u8 = 0xFF
	#partial switch cond.kind {
	case .CmpEq:
		op = 0x84 // 0F 84 cd JE rel32
	case .CmpNeq:
		op = 0x85 // 0F 85 cd JNE rel32
	case .CmpULt:
		op = 0x82 // 0F 82 cd JB rel32
	case .CmpULe:
		op = 0x86 // 0F 86 cd JBE rel32
	case .CmpSLt:
		op = 0x8c // 0F 8C cd JL rel32
	case .CmpSLe:
		op = 0x8e // 0F 8E cd JLE rel32
	case .CmpFLt: // float cmps apparantly set the unsigned "below" and "above" flags at least according to llvm output
		op = 0x82 // 0F 82 cd JB rel32
	case .CmpFLe:
		op = 0x86 // 0F 86 cd JBE rel32
	}

	return op if rel_size == 32 else op - 16
}

rex_prefix :: proc(dst: int, src: int, idx: int, is_wide: bool) -> u8 {
	assert(dst >= -1 && dst < 16)
	assert(src >= -1 && src < 16)
	assert(idx >= -1 && idx < 16)

	rex: u8 = 0x40
	if is_wide do rex |= 0x08 // REX.W: enables 64-bit registers
	if dst >= 8 do rex |= 0x04 // REX.R adds an extra bit to the reg field in the modrm byte
	if idx >= 8 do rex |= 0x02 // REX.X adds an extra bit to the index field in the modrm byte
	if src >= 8 do rex |= 0x01 // REX.B adds an extra bit to the r/m field in the modrm byte or in the sib base field
	return rex
}

MODAddressingMode :: enum(u8) {
	Indirect, // (%reg)
	IndirectDisp8, // 0x12(%reg)
	IndirectDisp32, // 0x12345678(%reg)
	Direct // %reg
}

modrm_byte :: proc(mod: MODAddressingMode, dst: int, src: int) -> u8 {
	dst2 := 0 if dst == -1 else dst
	assert(src >= 0 && src < 16)
	mod_field := (u8(mod) & 0x03) << 6
	reg := (u8(dst2) & 0x07) << 3
	rm := u8(src) & 0x07
	return mod_field | reg | rm
}


sib_byte :: proc(scale: int, index: int, base: int) -> u8 {
	assert(scale >= 0 && scale <= 4)
	assert(index >= 0 && index < 16)
	assert(base >= 0 && base < 16)
	return u8(scale << 6) | u8((index & 0x07) << 3) | u8(base & 0x07)
}


amd64_encoding_size :: proc(n: ^Node, delta_from_start_to_target: int) -> int {
	uop := Amd64Insr(n.uop)
	size := 0
	#partial switch uop {
	case .Jmp:
		if n.kind == .Branch {
			size = 2 if amd64_is_imm8(delta_from_start_to_target - 2) else 6
		} else {
			size = 2 if amd64_is_imm8(delta_from_start_to_target - 2) else 5
		}
	case .Call:
		size = 5
	case:
		panic("invalid uop encoding_size call")
	}
	return size
}

amd64_patch_local_relo :: proc(fn: ^Function, n: ^Node, start: int, delta_from_start_to_target: int) {
	out := &fn.output.data
	uop := Amd64Insr(n.uop)
	#partial switch uop {
	case .Jmp:
		if n.kind == .Branch {
			is_imm8 := amd64_is_imm8(delta_from_start_to_target - 2)
			op_size := 1 if is_imm8 else 2
			encoding_size := 2 if is_imm8 else 6 // We have a prefix 0x0F on Jcc, so it's not 5
			if !is_imm8 {
				op := amd64_get_br_jump_op(n, 32)
				fn.output.data[start] = 0x0F
				fn.output.data[start + 1] = op
			}
			delta := delta_from_start_to_target - encoding_size
			patch_into_output(&fn.output.data, start + op_size, start + encoding_size, delta)
		} else {
			op_size := 1
			is_imm8 := amd64_is_imm8(delta_from_start_to_target - 2)
			encoding_size := 2 if is_imm8 else 5
			delta := delta_from_start_to_target - encoding_size
			patch_into_output(&fn.output.data, start + op_size, start + encoding_size, delta)
		}
	case .Call:
		op_size := 1
		encoding_size := 5
		delta := delta_from_start_to_target - encoding_size
		patch_into_output(&fn.output.data, start + op_size, start + encoding_size, delta)
	case:
		panic("invalid patch insr")
	}

	patch_into_output :: proc(out: ^[dynamic]u8, start, end: int, delta: int) {
		to_slice := out[start:end]
		bytes := end - start
		for i := bytes - 1; i >= 0; i -= 1 {
			to_slice[i] = u8((delta >> 8 * i) & 0xFF)
		}
	}
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

amd64_get_dst_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	table_ent := &insr_table[Amd64Insr(n.uop)]

	if amd64_is_two_address_op(ctx, n){
		two_addr_lrg := find_live_range(ctx, n.inputs[table_ent.two_address_index])
		return ctx.lrg_store[merge_live_range(ctx, two_addr_lrg, n)].available_mask
	}

	regmask := transmute(RegisterMask)table_ent.out_regmask
	uop := Amd64Insr(n.uop)
	#partial switch uop {
		case .Proj:
			regmask = amd64_get_dst_regmask(ctx, n.inputs[0])
		case .Call:
			regmask = impl_amd64.abi[int(DEBUG_ABI)].return_regs
	}
	return regmask // some insrs are allowed to not produce any regs (Stores for example)
}

amd64_get_kill_regmask :: proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask {
	assert(n != nil)
	assert(n.uop != 0)
	uop := Amd64Insr(n.uop)
	regmask := transmute(RegisterMask)insr_table[uop].killmap
	#partial switch uop {
		case .Call:
			regmask = impl_amd64.abi[int(DEBUG_ABI)].caller_saved_regs
	}
	return regmask // some insrs are allowed to not produce any regs (Stores for example)
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
	.Proj = { { { insr = .Proj } } },
	.IntConst = {},
	.F32Const = {},
	.F64Const = {},
	.Local = { { { insr = .Local } } },
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
	.GetMemberPtr = { { { insr = .GetMemberPtr } } },
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
	killmap:           Amd64RegMask,
}

insr_table := [Amd64Insr]InsrTableEntry {
	.Invalid = { },
	.Proj = { in_regmask = {}, out_regmask = {} },
	.Local = { in_regmask = {}, out_regmask = transmute(Amd64RegMask)SPILL_MASK },
	.Ret = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Call = { /* this gets set on insr select */ in_regmask = {}, out_regmask = {} },
	.Jmp = { in_regmask = FLAGS_MASK, out_regmask = {} },
	.Load = { in_regmask = GPR_READ_MASK, out_regmask = GPR_WRITE_MASK },
	.GetMemberPtr = { in_regmask = GPR_READ_MASK | transmute(Amd64RegMask)SPILL_MASK, out_regmask = GPR_WRITE_MASK },
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
