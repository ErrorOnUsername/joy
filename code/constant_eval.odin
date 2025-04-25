package main

import "core:sync"

get_string_literal_value :: proc(ctx: ^CheckerContext, lit: ^StringLiteralExpr) -> bool {
	char_count := 0
	i := 0
	for {
		if i >= len(lit.str) {
			break
		}

		char_count += 1
		c := lit.str[i]
		if c == '\\' {
			i += 1
		}
		i += 1
	}

	mod := ctx.checker.cg_module

	sync.lock(&mod.allocator_lock)
	val := make([]u8, char_count + 1, ctx.checker.cg_module.allocator)
	sync.unlock(&mod.allocator_lock)

	i = 0
	write_idx := 0
	for {
		if i >= len(lit.str) {
			break
		}

		c := lit.str[i]
		to_add := c
		if c == '\\' {
			if i + 1 >= len(lit.str) {
				log_spanned_error(&lit.span, "expected escape character (t, v, r, n, e)!")
				return false
			}
			e := lit.str[i+1]
			switch e {
				case 't': to_add = '\t'
				case 'v': to_add = '\v'
				case 'r': to_add = '\r'
				case 'n': to_add = '\n'
				case 'e': to_add = '\e'
				case:     to_add = e
			}
			i += 1
		}

		val[write_idx] = to_add

		i += 1
		write_idx += 1
	}
	val[char_count] = 0

	lit.val = val

	return true
}

get_number_literal_value :: proc(ctx: ^CheckerContext, lit: ^NumberLiteralExpr) -> bool {
	is_float := false
	base := 10

	if len(lit.str) > 1 && lit.str[0] == '0' {
		base_discr := lit.str[1]
		switch base_discr {
			case 'x': base = 16
			case 'o': base = 8
			case 'b': base = 2
			case '.':
				is_float = true
				base = 10 // special.. just for floats so this shit don't explode
			case:
				log_spanned_errorf(&lit.span, "Invalid number literal base '{:c}'. Expected 'x' (hexadecimal), 'o' (octal), or 'b' (binary)", base_discr)
				return false
		}
	}

	num_slice_offset := 2 if base != 10 else 0
	num_str := lit.str[num_slice_offset:]

	for c in num_str {
	}

	return true
}

