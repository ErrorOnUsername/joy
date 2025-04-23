package main

get_string_literal_value :: proc(ctx: ^CheckerContext, lit: ^StringLiteralExpr) -> bool {
	char_count := 0
	for i in len(lit.str) {
		char_count += 1
		c := lit.str[i]
		if c == '\\' {
			i += 1
		}
	}

	val := make([]u8, char_count, ctx.checker.cg_module)
	for i in len(lit.str) {
		c := lit.str[i]
	}
}

