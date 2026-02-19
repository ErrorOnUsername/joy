package main

import "core:fmt"
import "core:sys/info"

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
	if info.os_version.platform == .Windows {
		platform = .Windows
	} else if info.os_version.platform == .iOS || info.os_version.platform == .MacOS {
		platform = .MacOS
	} else if info.os_version.platform == .Linux {
		platform = .Linux
	}

	arch: Architecture
	arch = .Amd64
	fmt.println("forcing to amd64 architecture")

	return { arch, platform }
}

target_get_word_size :: proc(target: TargetDesc) -> int {
	#partial switch target.arch {
		case .Amd64:
			return 8
	}

	unreachable()
}
