package main

import "core:strings"

StateNode :: struct
{
	char:    u8,
	tk_kind: TokenKind,
	next:    []StateNode,
}

TokenParseStateTree :: struct
{
	nodes: []StateNode,
}

parse_state_tree := TokenParseStateTree {
	{
		{
			char    = ':',
			tk_kind = .Colon,
			next    = {
				{
					char    = '=',
					tk_kind = .ColonAssign,
					next    = {},
				},
			},
		},
		{ ';', .Semicolon, {} },
		{ ',', .Comma, {} },
		{
			char    = '.',
			tk_kind = .Dot,
			next    = {
				{
					char    = '.',
					tk_kind = .DotDot,
					next    = { },
				},
			},
		},
		{ '(', .LParen, {} },
		{ ')', .RParen, {} },
		{ '{', .LCurly, {} },
		{ '}', .RCurly, {} },
		{ '[', .LSquare, {} },
		{ ']', .RSquare, {} },
		{
			char    = '=',
			tk_kind = .Assign,
			next    = {
				{
					char    = '=',
					tk_kind = .Equal,
					next    = {},
				},
			},
		},
		{
			char    = '!',
			tk_kind = .Bang,
			next    = {
				{
					char    = '=',
					tk_kind = .NotEqual,
					next    = {},
				},
			},
		},
		{ '~', .Tilde, {}, },
		{
			char    = '&',
			tk_kind = .Ampersand,
			next    = {
				{
					char    = '=',
					tk_kind = .AmpersandAssign,
					next    = {},
				},
				{
					char    = '&',
					tk_kind = .DoubleAmpersand,
					next    = {},
				},
			},
		},
		{
			char    = '|',
			tk_kind = .Pipe,
			next    = {
				{
					char    = '=',
					tk_kind = .PipeAssign,
					next    = {},
				},
				{
					char    = '|',
					tk_kind = .DoublePipe,
					next    = {},
				},
			},
		},
		{
			char    = '^',
			tk_kind = .Caret,
			next    = {
				{
					char    = '=',
					tk_kind = .CaretAssign,
					next    = {},
				},
				{
					char    = '^',
					tk_kind = .DoubleCaret,
					next    = {},
				},
			},
		},
		{
			char    = '<',
			tk_kind = .LAngle,
			next    = {
				{
					char    = '<',
					tk_kind = .LShift,
					next    = {}, // TODO: Arithmetic shift?
				},
				{
					char    = '=',
					tk_kind = .LessThanOrEqual,
					next    = {},
				},
			},
		},
		{
			char    = '>',
			tk_kind = .RAngle,
			next    = {
				{
					char    = '>',
					tk_kind = .RShift,
					next    = {}, // TODO: Arithmetic shift?
				},
				{
					char    = '=',
					tk_kind = .GreaterThanOrEqual,
					next    = {},
				},
			},
		},
		{
			char    = '+',
			tk_kind = .Plus,
			next    = {
				{
					char    = '+',
					tk_kind = .PlusPlus,
					next    = {},
				},
				{
					char    = '=',
					tk_kind = .PlusAssign,
					next    = {},
				},
			},
		},
		{
			char    = '-',
			tk_kind = .Minus,
			next    = {
				{
					char    = '-',
					tk_kind = .MinusMinus,
					next    = {},
				},
				{
					char    = '=',
					tk_kind = .MinusAssign,
					next    = {},
				},
				{
					char    = '>',
					tk_kind = .SmolArrow,
					next    = {},
				},
			},
		},
		{
			char    = '*',
			tk_kind = .Star,
			next    = {
				{
					char    = '=',
					tk_kind = .StarAssign,
					next    = {},
				},
			},
		},
		{
			char    = '/',
			tk_kind = .Slash,
			next    = {
				{
					char    = '=',
					tk_kind = .SlashAssign,
					next    = {},
				},
			},
		},
		{
			char    = '%',
			tk_kind = .Percent,
			next    = {
				{
					char    = '=',
					tk_kind = .PercentAssign,
					next    = {},
				},
			},
		},
	},
}

try_lex_from_parse_tree_node :: proc( data: ^FileData, token: ^Token, nodes: []StateNode ) -> bool
{
	token.kind       = .Invalid
	token.span.file  = data.id
	token.span.start = data.read_idx
	token.span.end   = data.read_idx + 1

	ch := data.data[data.read_idx]

	current_node_list := nodes
	idx               := 0

	for {
		if len( current_node_list ) == 0 || idx == len( current_node_list ) do break

		node := &current_node_list[idx]

		if node.char == ch {
			token.kind     = node.tk_kind
			token.span.end = data.read_idx + 1

			data.read_idx += 1
			ch = data.data[data.read_idx]

			current_node_list = node.next
			idx               = 0

			continue
		}

		idx += 1
	}

	return token.kind != .Invalid
}

tokenize_file :: proc( data: ^FileData ) -> bool
{
	tk := Token { }
	ok := lex_next_token( data, &tk )

	if !ok do return false

	for tk.kind != .Invalid {
		append( &data.tokens, tk )

		if tk.kind == .EndOfFile do break

		ok = lex_next_token( data, &tk )
		if !ok do return false
	}

	return true
}

lex_next_token :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
	token^ = { }

	if data.read_idx >= len( data.data ) {
		end := len( data.data )

		token.kind = .EndOfFile
		token.span = { data.id, uint( end - 1 ), uint( end ) }
		return
	}

	for data.data[data.read_idx] == ' ' || data.data[data.read_idx] == '\t' {
		data.read_idx += 1
	}

	full_data_len := uint( len( data.data ) )

	parse_tree_res_ok := try_lex_from_parse_tree_node( data, token, parse_state_tree.nodes )

	if !parse_tree_res_ok {
		start_ch := data.data[data.read_idx]

		switch start_ch {
			case '\r':
				if data.data[data.read_idx + 1] != '\n' {
					log_errorf( "Carriage return not followed by newline??? Got {:q} instead", rune( data.data[data.read_idx + 1] ) )
					token.kind = .Invalid
					ok = false
				} else {
					token.kind = .EndOfLine
				}

				token.span = { data.id, data.read_idx, data.read_idx + 2 }
				data.read_idx += 2
			case '\n':
				data.read_idx += 1

				token.kind = .EndOfLine
				token.span = { data.id, data.read_idx - 1, data.read_idx }
			case '"':
				ok = get_string_literal( data, token )
			case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
				ok = get_number_literal( data, token )
			case:
				ok = get_ident_or_keword( data, token )
		}
	}

	if token.kind != .Invalid && len( token.str ) == 0 {
		token.str = data.data[token.span.start:token.span.end]
	}

	return
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
	"decl"     = .Decl,
	"let"      = .Let,
	"struct"   = .Struct,
	"enum"     = .Enum,
	"union"    = .Union,
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

tk_to_bin_op :: proc( tk: ^Token ) -> BinaryOperator
{
	#partial switch tk.kind {
		case .Assign:             return .Assign
		case .Equal:              return .Equal
		case .Dot:                return .MemberAccess
		case .DotDot:             return .Range
		case .Plus:               return .Add
		case .PlusAssign:         return .AddAssign
		case .Minus:              return .Subtract
		case .MinusAssign:        return .SubtractAssign
		case .Star:               return .Multiply
		case .StarAssign:         return .MultiplyAssign
		case .Slash:              return .Divide
		case .SlashAssign:        return .DivideAssign
		case .Percent:            return .Modulo
		case .PercentAssign:      return .ModuloAssign
		case .LAngle:             return .LessThan
		case .LessThanOrEqual:    return .LessThanOrEq
		case .LShift:             return .BitwiseLShift
		case .RAngle:             return .GreaterThan
		case .GreaterThanOrEqual: return .GreaterThanOrEq
		case .RShift:             return .BitwiseRShift
		case .NotEqual:           return .NotEqual
		case .Ampersand:          return .BitwiseAnd
		case .DoubleAmpersand:    return .LogicalAnd
		case .AmpersandAssign:    return .AndAssign
		case .Pipe:               return .BitwiseOr
		case .DoublePipe:         return .LogicalOr
		case .PipeAssign:         return .OrAssign
		case .Caret:              return .BitwiseXOr
		case .DoubleCaret:        return .LogicalXOr
		case .CaretAssign:        return .XOrAssign
	}

	return .Invalid
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

	EndOfLine,
	EndOfFile,

	Decl,
	Let,

	Struct,
	Enum,
	Union,

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
	PlusPlus,
	PlusAssign,
	Minus,
	MinusMinus,
	MinusAssign,
	Star,
	StarAssign,
	Slash,
	SlashAssign,
	Percent,
	PercentAssign,

	SmolArrow,

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

	Ampersand,
	DoubleAmpersand,
	AmpersandAssign,
	Pipe,
	DoublePipe,
	PipeAssign,
	Caret,
	DoubleCaret,
	CaretAssign,

	Continue,
	Break,
	In,

	If,
	Else,
	For,
	While,
	Loop,

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

