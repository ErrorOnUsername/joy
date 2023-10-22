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
		{ '.', .Dot, {} },
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
		log_warningf( "tk: {}", tk )

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
				token.span = { data.id, data.read_idx, data.read_idx + 1 }
				log_error( "implement number literal parsing" )
				ok = false
			case:
				ok = get_ident_or_keword( data, token )
		}
	}

	if token.kind != .Invalid && len( token.str ) == 0 {
		token.str = data.data[token.span.start:token.span.end]
	}

	return
}

get_string_literal :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
	data.read_idx += 1

	sb := strings.builder_make()
	defer strings.builder_destroy( &sb )

	data_size       := uint( len( data.data ) )
	start           := data.read_idx - 1
	found_end_quote := false

	for !found_end_quote && data.read_idx < data_size {
		c := data.data[data.read_idx]
		if c == '\\' {
			esc_c := data.data[data.read_idx + 1]

			switch esc_c {
				case 'r':
					strings.write_byte( &sb, '\r' )
				case 'n':
					strings.write_byte( &sb, '\n' )
				case 'e':
					strings.write_byte( &sb, '\x1b' )
				case 't':
					strings.write_byte( &sb, '\t' )
				case 'x':
					log_error( "implement hexadecimal string escapes (i.e. '\\x1b')" )
					ok = false
					return
				case:
					strings.write_byte( &sb, esc_c )
			}

			data.read_idx += 2
			continue
		}

		if c == '"' {
			found_end_quote = true
		} else {
			strings.write_byte( &sb, c )
		}

		data.read_idx += 1
	}

	token.span = { data.id, start, data.read_idx - 1 }

	if !found_end_quote {
		log_error( "Unterminated string literal" )
		ok = false
	} else {
		token.kind = .String
		token.str, _  = strings.clone( strings.to_string( sb ) )
	}

	return
}

keyword_map := map[string]TokenKind {
	"decl"   = .Decl,
	"let"    = .Let,
	"struct" = .Struct,
	"enum"   = .Enum,
	"union"  = .Union,
	"u8"     = .U8,
	"i8"     = .I8,
	"u16"    = .U16,
	"i16"    = .I16,
	"u32"    = .U32,
	"i32"    = .I32,
	"u64"    = .U64,
	"i64"    = .I64,
	"f32"    = .F32,
	"f64"    = .F64,
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
		// TODO: Impl
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
	String,
	Number,

	Assign,
	Equal,

	Semicolon,
	Comma,
	Dot,
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

	U8,
	I8,
	U16,
	I16,
	U32,
	I32,
	U64,
	I64,
	F32,
	F64,
}

