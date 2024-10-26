package main

import "core:os"

Architecture :: enum {
	Invalid,
	Amd64,
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
	when os.OS == .Windows {
		platform = .Windows
	} else when os.OS == .Darwin {
		platform = .MacOS
	} else when os.OS == .Linux {
		platform = .Linux
	}

	arch: Architecture
	when os.ARCH == .amd64 {
		arch = .Amd64
	}

	return { arch, platform }
}

target_get_word_size :: proc(target: TargetDesc) -> int {
	#partial switch target.arch {
		case .Amd64:
			return 8
	}

	unreachable()
}
