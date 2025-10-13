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
