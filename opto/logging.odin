package opto

import "core:fmt"
import "core:strings"


PRINT_LOGS :: true

log :: proc(fn: ^Function, msg: string, args: ..any) {
	msg_builder: strings.Builder
	defer strings.builder_destroy(&msg_builder)
	fmt.sbprintf(&msg_builder, "[{}] ", fn.name)
	fmt.sbprintf(&msg_builder, msg, ..args)
	fmt_msg := strings.to_string(msg_builder)
	fnl_msg := strings.clone(fmt_msg)
	append(&fn.meta.logs, fnl_msg)
	when PRINT_LOGS {
		fmt.println(fnl_msg)
	}
}
