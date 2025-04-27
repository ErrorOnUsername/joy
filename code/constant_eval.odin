package main

import "core:sync"
import "core:strconv"
import "core:strings"
import "core:math/big"

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

get_digit_for_base :: proc(d: u8, base: int) -> (u8, bool) {
	if d >= '0' && d <= '1' do return d - '0', base >= 2
	if d >= '2' && d <= '7' do return d - '0', base >= 8
	if d >= '8' && d <= '9' do return d - '0', base >= 10
	if d >= 'a' && d <= 'f' do return d - 'a', base >= 16
	if d >= 'A' && d <= 'A' do return d - 'A', base >= 16

	return 0, false
}

get_number_literal_value :: proc(ctx: ^CheckerContext, lit: ^NumberLiteralExpr) -> bool {
	base := 10

	if len(lit.str) > 1 && lit.str[0] == '0' {
		base_discr := lit.str[1]
		switch base_discr {
			case 'x': base = 16
			case 'o': base = 8
			case 'b': base = 2
			case '.': base = 10 // special.. just for floats so this shit don't explode
			case:
				log_spanned_errorf(&lit.span, "Invalid number literal base '{:c}'. Expected 'x' (hexadecimal), 'o' (octal), or 'b' (binary)", base_discr)
				return false
		}
	}

	is_float := strings.contains(lit.str, ".")

	if is_float {
		val, ok := strconv.parse_f64(lit.str)
		if !ok {
			// This error kinda sucks and is unhelpful so we may have to write custom parsing to make it not ass
			log_spanned_error(&lit.span, "Invalid floating point literal")
			return false
		}

		lit.val = val

		return true
	}

	base_bigint: big.Int
	big.set(&base_bigint, base)
	defer big.destroy(&base_bigint)

	val: big.Int

	num_slice_offset := 2 if base != 10 else 0
	int_str := lit.str[num_slice_offset:]

	temp: big.Int
	defer big.destroy(&temp)
	for c in int_str {
		if c == '_' {
			num_slice_offset += 1
			continue
		}

		digit, is_digit := get_digit_for_base(u8(c), base)
		if !is_digit do break

		big.mul(&temp, &val, &base_bigint)
		big.set(&val, &temp) // val = val * base

		big.add(&temp, &val, big.DIGIT(digit))
		big.set(&val, &temp) // val = val + digit

		num_slice_offset += 1
	}

	if num_slice_offset < len(lit.str) {
		end := lit.str[num_slice_offset]
		if end != 'e' && end != 'E' {
			log_spanned_error(&lit.span, "Invalid integer literal suffix")
			return false
		}

		exp := 0
		expr_str := lit.str[num_slice_offset + 1:]
		for c in expr_str {
			digit, is_valid := get_digit_for_base(u8(c), 10)
			if !is_valid {
				log_spanned_error(&lit.span, "Integer exponent must be in base 10")
				return false
			}

			exp *= 10
			exp += int(digit)
		}

		factor: big.Int
		defer big.destroy(&factor)

		big.pow(&temp, 10, exp)
		big.set(&factor, &temp) // factor = 10^exp

		big.mul(&temp, &val, &factor)
		big.set(&val, &temp) // val = val * factor
	}

	lit.val = val

	return true
}

