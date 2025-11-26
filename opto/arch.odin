package opto


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
	get_src_regmask: #type proc(n: ^Node) -> RegisterMask,
	get_dst_regmask: #type proc(n: ^Node) -> RegisterMask,
}

PlatformABI :: struct {
	// Theres more then one because sysv is just cool like that for some fucking reason
	return_regs: RegisterMask,
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
