package epoch

import "core:fmt"
import "core:strings"


log :: proc(fn: ^Function, msg: string, args: ..any) {
	msg_builder: strings.Builder
	defer strings.builder_destroy(&msg_builder)
	fmt.sbprintf(&msg_builder, "[{}] ", fn.name)
	fmt.sbprintf(&msg_builder, msg, ..args)
	fmt_msg := strings.to_string(msg_builder)
	fnl_msg := strings.clone(fmt_msg)
	append(&fn.meta.logs, fnl_msg)
}


dump_logs :: proc(fn: ^Function) {
	for msg in fn.meta.logs {
		fmt.println(msg)
	}
}

