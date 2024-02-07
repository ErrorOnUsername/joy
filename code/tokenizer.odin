package main

import "core:strings"

tokenize_file :: proc( data: ^FileData ) -> bool
{
	tk := lex_next_token( data )
	for tk.kind != .EndOfFile {
		if tk.kind == .Invalid {
			log_spanned_error( &tk.span, "got invalid token" )
			return false
		}
		append( &data.tokens, tk )
		tk = lex_next_token( data )
	}

	return true
}

lex_next_token :: proc( data: ^FileData ) -> ( token: Token )
{
	data_size := uint( len( data.data ) )

	for data.read_idx < data_size {
		c := data.data[data.read_idx]

		switch c {
			case ' ':
				data.read_idx += 1
			case '\r':
				data.read_idx += 1
				assert( data.data[data.read_idx] == '\n' )
				data.read_idx += 1
				token.kind = .EndOfLine
				lex_assign_span( data, &token, 2 )
			case '\n':
				data.read_idx += 1
				token.kind = .EndOfLine
				lex_assign_span( data, &token, 2 )
			case '=':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .Equal
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '>' ) {
					token.kind = .ThiccArrow
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Assign
					lex_assign_span( data, &token, 1 )
				}
				return
			case ';':
				data.read_idx += 1
				token.kind = .Semicolon
				lex_assign_span( data, &token, 1 )
				return
			case ',':
				data.read_idx += 1
				token.kind = .Comma
				lex_assign_span( data, &token, 1 )
				return
			case '.':
				data.read_idx += 1
				if lex_try_consume( data, '.' ) {
					token.kind = .DotDot
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Dot
					lex_assign_span( data, &token, 1 )
				}
				return
			case '~':
				data.read_idx += 1
				token.kind = .Tilde
				lex_assign_span( data, &token, 1 )
				return
			case ':':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .ColonAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Colon
					lex_assign_span( data, &token, 1 )
				}
				return
			case '+':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .PlusAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Plus
					lex_assign_span( data, &token, 1 )
				}
				return
			case '-':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .MinusAssign
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '>' ) {
					token.kind = .SmolArrow
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Minus
					lex_assign_span( data, &token, 1 )
				}
				return
			case '*':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .StarAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Star
					lex_assign_span( data, &token, 1 )
				}
				return
			case '/':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .SlashAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Slash
					lex_assign_span( data, &token, 1 )
				}
				return
			case '%':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .PercentAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Percent
					lex_assign_span( data, &token, 1 )
				}
				return
			case '(':
				data.read_idx += 1
				token.kind = .LParen
				lex_assign_span( data, &token, 1 )
			case ')':
				data.read_idx += 1
				token.kind = .RParen
				lex_assign_span( data, &token, 1 )
			case '{':
				data.read_idx += 1
				token.kind = .LCurly
				lex_assign_span( data, &token, 1 )
			case '}':
				data.read_idx += 1
				token.kind = .RCurly
				lex_assign_span( data, &token, 1 )
			case '[':
				data.read_idx += 1
				token.kind = .LSquare
				lex_assign_span( data, &token, 1 )
			case ']':
				data.read_idx += 1
				token.kind = .RSquare
				lex_assign_span( data, &token, 1 )
			case '<':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .LessThanOrEqual
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '<' ) {
					token.kind = .LShift
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .LAngle
					lex_assign_span( data, &token, 1 )
				}
			case '>':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .GreaterThanOrEqual
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '>' ) {
					token.kind = .RShift
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .RAngle
					lex_assign_span( data, &token, 1 )
				}
			case '!':
				data.read_idx += 1
				if lex_try_consume( data, '=' ) {
					token.kind = .NotEqual
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Bang
					lex_assign_span( data, &token, 1 )
				}
				return
			case '@':
				data.read_idx += 1
				lex_assign_span( data, &token, 1 )
				return
			case '&':
				data.read_idx += 1
				if lex_try_consume( data, '&' ) {
					token.kind = .DoubleAmpersand
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '=' ) {
					token.kind = .AmpersandAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Ampersand
					lex_assign_span( data, &token, 1 )
				}
				return
			case '|':
				data.read_idx += 1
				if lex_try_consume( data, '|' ) {
					token.kind = .DoublePipe
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '=' ) {
					token.kind = .PipeAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Pipe
					lex_assign_span( data, &token, 1 )
				}
				return
			case '^':
				data.read_idx += 1
				if lex_try_consume( data, '^' ) {
					token.kind = .DoubleCaret
					lex_assign_span( data, &token, 2 )
				} else if lex_try_consume( data, '=' ) {
					token.kind = .CaretAssign
					lex_assign_span( data, &token, 2 )
				} else {
					token.kind = .Caret
					lex_assign_span( data, &token, 1 )
				}
				return
			case '"':
				ok := get_string_literal( data, &token )
				if !ok {
					token.kind = .Invalid
					return
				}
				return
			case '0'..='9':
				ok := get_number_literal( data, &token )
				if !ok {
					token.kind = .Invalid
					return
				}
				return
			case 'a'..='z', 'A'..='Z', '_':
				ok := get_ident_or_keword( data, &token )
				if !ok {
					token.kind = .Invalid
					return
				}
				return
			case:
				data.read_idx += 1
				token.kind = .Invalid
				lex_assign_span( data, &token, 1 )
				return
		}
	}

	token.kind = .EndOfFile
	token.span = { data.id, data_size - 1, data_size }
	return
}

lex_try_consume :: proc( data: ^FileData, c: u8 ) -> bool
{
	if data.data[data.read_idx] == c {
		data.read_idx += 1
		return true
	}

	return false
}

lex_assign_span :: proc( data: ^FileData, t: ^Token, size: uint )
{
	t.span.file = data.id
	t.span.start = data.read_idx - size
	t.span.end = data.read_idx
}

is_digit_char :: proc( char: u8 ) -> bool
{
	return ( char >= '0' && char <= '9' ) || ( char >= 'a' && char <= 'f' ) || ( char >= 'A' && char <= 'F' )
}

is_valid_number_char :: proc( char: u8 ) -> bool
{
	return is_digit_char( char ) || char == '.' || char == '_'
}

get_number_literal :: proc( data: ^FileData, token: ^Token ) -> bool
{
	token.kind = .Number
	token.span = { data.id, data.read_idx, data.read_idx + 1 }

	found_dot := false
	ch := data.data[data.read_idx]

	radix := 10

	if ch == '0' {
		data.read_idx  += 1
		token.span.end += 1

		base_ch := data.data[data.read_idx]

		switch base_ch {
			case 'b': radix = 2; data.read_idx += 1; token.span.end += 1
			case 'o': radix = 8; data.read_idx += 1; token.span.end += 1
			case 'x': radix = 16; data.read_idx += 1; token.span.end += 1
			case:
		}

		ch = data.data[data.read_idx]

		if radix == 10 && is_digit_char( ch ) {
			log_spanned_error( &token.span, "Leading zero in number literal" )
			return false
		}

		if radix != 10 && !is_digit_char( ch ) {
			log_spanned_error( &token.span, "Base prefix not followed by number value" )
			return false
		}
	}

	for ch != '\n' && is_valid_number_char( ch ) {
		if ch == '.' {
			if !is_digit_char( data.data[data.read_idx + 1] ) {
				// Special case for '..'
				token.span.end -= 1
				return true
			}

			if radix != 10 {
				token.span.start = data.read_idx
				log_spanned_error( &token.span, "Cannot specify a fractional component in non-decimal number systems" )
				return false
			}

			if found_dot {
				token.span.end -= 1
				return true
			}

			found_dot = true
		}

		if ch == '_' {
			if !( is_digit_char( data.data[data.read_idx - 1] ) && is_digit_char( data.data[data.read_idx + 1] ) ) {
				token.span.start = data.read_idx
				log_spanned_error( &token.span, "Digit seperator char must be between two digits" )
				return false
			}
		}


		token.span.end += 1
		data.read_idx += 1
		ch = data.data[data.read_idx]
	}

	token.span.end -= 1

	return true
}

get_string_literal :: proc( data: ^FileData, token: ^Token ) -> bool
{
	token.kind = .StringLiteral
	token.span = { data.id, data.read_idx, data.read_idx + 1 }

	data.read_idx += 1

	ch := data.data[data.read_idx]
	for ch != '\n' && ch != '"' {
		data.read_idx += 1
		token.span.end += 1
		ch = data.data[data.read_idx]
	}

	if ch == '\n' {
		log_spanned_error( &token.span, "Unterminated string literal!" )
		return false
	}

	data.read_idx += 1
	token.span.end += 1

	return true
}

keyword_map := map[string]TokenKind {
	"void"     = .Void,
	"decl"     = .Decl,
	"let"      = .Let,
	"struct"   = .Struct,
	"enum"     = .Enum,
	"union"    = .Union,
	"proc"     = .Proc,
	"return"   = .Return,
	"continue" = .Continue,
	"break"    = .Break,
	"in"       = .In,
	"if"       = .If,
	"else"     = .Else,
	"for"      = .For,
	"while"    = .While,
	"loop"     = .Loop,
	"bool"     = .Bool,
	"u8"       = .U8,
	"i8"       = .I8,
	"u16"      = .U16,
	"i16"      = .I16,
	"u32"      = .U32,
	"i32"      = .I32,
	"u64"      = .U64,
	"i64"      = .I64,
	"usize"    = .USize,
	"isize"    = .ISize,
	"f32"      = .F32,
	"f64"      = .F64,
	"string"   = .String,
	"cstring"  = .CString,
	"rawptr"   = .RawPtr,
	"range"    = .Range,
}

get_ident_or_keword :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
	start := data.read_idx
	for is_valid_ident_char( data.data[data.read_idx] )
	{
		data.read_idx += 1
	}

	ident_slice := data.data[start:data.read_idx]

	token.span = { data.id, start, data.read_idx }

	if ident_slice in keyword_map {
		token.kind = keyword_map[ident_slice]
	} else {
		token.kind = .Ident
		token.str  = ident_slice
	}

	return
}

is_valid_ident_char :: proc( c: u8 ) -> bool
{
	return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'
}

join_span :: proc( l_span: ^Span, r_span: ^Span ) -> ( ret: Span, ok := true )
{
	ret = {}

	if l_span.file != r_span.file {
		ok = false
		log_errorf( "left span '{}' and right span '{}' are not in the same file!", l_span, r_span )
		return
	}

	if l_span.start > r_span.end {
		ok = false
		log_errorf( "left span '{}' comes after right span '{}'!", l_span, r_span )
		return
	}

	ret.file  = l_span.file
	ret.start = l_span.start
	ret.end   = r_span.end

	return
}


Span :: struct
{
	file:  FileID,
	start: uint,
	end:   uint,
}

Token :: struct
{
	kind: TokenKind,
	span: Span,
	str:  string,
}

TokenKind :: enum
{
	Invalid,

	EndOfFile,
	EndOfLine,

	Decl,
	Let,

	Struct,
	Enum,
	Union,
	Proc,

	Ident,
	StringLiteral,
	Number,

	Assign,
	Equal,

	Semicolon,
	Comma,
	Dot,
	DotDot,
	Tilde,

	Colon,
	ColonAssign,

	Plus,
	PlusAssign,
	Minus,
	MinusAssign,
	Star,
	StarAssign,
	Slash,
	SlashAssign,
	Percent,
	PercentAssign,

	SmolArrow,
	ThiccArrow,

	LParen,
	RParen,
	LCurly,
	RCurly,
	LSquare,
	RSquare,

	LAngle,
	LessThanOrEqual,
	LShift,
	RAngle,
	GreaterThanOrEqual,
	RShift,

	Bang,
	NotEqual,

	At,
	Ampersand,
	DoubleAmpersand,
	AmpersandAssign,
	Pipe,
	DoublePipe,
	PipeAssign,
	Caret,
	DoubleCaret,
	CaretAssign,

	Return,
	Continue,
	Break,
	In,

	If,
	Else,
	For,
	While,
	Loop,

	Void,
	Bool,
	U8,
	I8,
	U16,
	I16,
	U32,
	I32,
	U64,
	I64,
	USize,
	ISize,
	F32,
	F64,
	String,
	CString,
	RawPtr,
	Range,
}

