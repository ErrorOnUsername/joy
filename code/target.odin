package main

import "core:fmt"
import "core:sys/info"
import "../opto"

Architecture :: enum {
	Invalid,
	Amd64,
	AArch64,
}

Platform :: enum {
	Invalid,
	Windows,
	MacOS,
	Linux,
}

TargetDesc :: struct {
	arch: Architecture,
	platform: Platform,
}

get_host_target_desc :: proc() -> TargetDesc {
	platform: Platform
	if info.os_version.platform == .Windows {
		platform = .Windows
	} else if info.os_version.platform == .iOS || info.os_version.platform == .MacOS {
		platform = .MacOS
	} else if info.os_version.platform == .Linux {
		platform = .Linux
	}

	arch: Architecture
	#partial switch ODIN_ARCH {
	case .amd64: arch = .Amd64
	case .arm64: arch = .AArch64
	case: panic("we don't support your host architecture :'(")
	}

	return { arch, platform }
}

target_get_word_size :: proc(target: TargetDesc) -> int {
	switch target.arch {
	case .Invalid:
	case .Amd64:
		return 8
	case .AArch64:
		return 8
	}

	unreachable()
}

to_opto_arch :: proc(arch: Architecture) -> opto.Arch {
	switch arch {
	case .Amd64: return .Amd64
	case .AArch64: return .AArch64
	case .Invalid:
	}
	panic("unknown arch")
}

to_opto_platform :: proc(plat: Platform) -> opto.Platform {
	switch plat {
	case .Invalid:
	case .Windows:
		return .Windows
	case .MacOS:
		return .Darwin
	case .Linux:
		return .Linux
	}
	panic("unknown platform")
}
