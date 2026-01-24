package opto

import "core:fmt"
import "core:strings"


Arch :: enum {
	Amd64,
}

// Opaque definitions that are specified in the architecture implementation
MachineOp :: u32
INVALID_OP :: MachineOp(0) // all archs should define this as INVALID since it's a sentinel state. Could also just use a Maybe but maybe you should sugma
RegisterID :: int
INVALID_REG :: RegisterID(-1)
RegisterMask :: int

ArchImpl :: struct {
	reg_names: []string,
	abi: []PlatformABI,
	select: #type proc(fn: ^Function, n: ^Node) -> MachineOp,
	encode: #type proc(fn: ^Function, n: ^Node) -> bool,
	get_callee_save_regmask: #type proc(ctx: ^RegAllocContext) -> RegisterMask,
	get_src_regmask: #type proc(ctx: ^RegAllocContext, n: ^Node, from: int) -> RegisterMask,
	get_dst_regmask: #type proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask,
	get_kill_regmask: #type proc(ctx: ^RegAllocContext, n: ^Node) -> RegisterMask, // some instructions kill registers (function calls for instance)
}

ABIParameterOrder :: enum {
	LeftToRight,
	RightToLeft,
}

PlatformABI :: struct {
	param_order:       ABIParameterOrder,
	param_stack_order: ABIParameterOrder,
	int_param_regs:    []RegisterMask,
	float_param_regs:  []RegisterMask,
	// Theres more then one because sysv is just cool like that for some fucking reason
	return_regs:       RegisterMask,
	caller_saved_regs: RegisterMask,
	callee_saved_regs: RegisterMask,
}

arch_impl :: proc(arch: Arch) -> ^ArchImpl {
	switch arch {
		case .Amd64:
			return &impl_amd64
	}
	return nil
}

arch_get_register_mask_str :: proc(arch: Arch, mask: RegisterMask) -> string {
	impl := arch_impl(arch)
	sb: strings.Builder
	if mask == 0 {
		fmt.sbprint(&sb, "<empty>")
	} else {
		bit_count := 0
		// unsigned loop... no underflows here nerd
		for i in 0..<(size_of(RegisterMask) * 8) {
			if mask & (1 << uint(i)) != 0 {
				if bit_count > 0 do fmt.sbprint(&sb, ", ")
				fmt.sbprintf(&sb, "{}", impl.reg_names[i])
				bit_count += 1
			}
		}
	}
	return strings.to_string(sb)
}

