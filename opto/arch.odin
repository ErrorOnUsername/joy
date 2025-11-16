package opto


Arch :: enum {
	Amd64,
}

// Opaque definitions that are specified in the architecture implementation
MachineOp :: u32
INVALID_OP :: MachineOp(~u32(0))
RegisterID :: int
INVALID_REG :: RegisterID(-1)
RegisterMask :: int

ARCH_TYPE_MASK :: NodeKindRaw(0xff << 24)

has_arch_mask :: proc(kind: NodeKindRaw) -> bool {
	return kind & ARCH_TYPE_MASK != 0
}

as_node_kind_raw :: proc(arch: Arch, op: MachineOp) -> NodeKindRaw {
	assert(int(arch) < 0xff)
	return ((NodeKindRaw(arch) + 1) << 24) | NodeKindRaw(op)
}

ArchImpl :: struct {
	reg_names: []string,
	abi: []PlatformABI,
	select: #type proc(fn: ^Function, n: ^Node) -> MachineOp,
	encode: #type proc(fn: ^Function, n: ^Node) -> bool,
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
