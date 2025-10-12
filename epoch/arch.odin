package epoch


Arch :: enum {
	Amd64,
}

// Opaque definitions that are specified in the architecture implementation
MachineOp :: int
INVALID_OP :: MachineOp(-1)

RegisterID :: int
INVALID_REG :: RegisterID(-1)

ArchImpl :: struct {
	reg_names: []string,
	abi: [Platform]PlatformABI,
	select: #type proc(n: ^Node) -> MachineOp,
}

Platform :: enum {
    Windows,
    SysV,
}

PlatformABI :: struct {
	caller_saved_regs: []RegisterID,
	callee_saved_regs: []RegisterID,
}

arch_impl :: proc(arch: Arch) -> ^ArchImpl {
	switch arch {
    	case .Amd64:
    		return &impl_amd64
	}
	return nil
}
