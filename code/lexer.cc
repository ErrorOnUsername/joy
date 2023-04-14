#include "lexer.hh"
#include <unordered_map>

#include "assert.hh"
#include "profiling.hh"


static void Lexer_SkipWhitespace( FileLexInfo& file_lex_info )
{
	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	while ( *read_head )
	{
		switch ( *read_head )
		{
			case '\r':
			case '\t':
			case '\v':
			case ' ':
				file_lex_info.cursor_position++;
				read_head++;
				continue;
		}

		break;
	}
}


static Token Lexer_ReadNumberLiteral( FileLexInfo& file_lex_info );
static Token Lexer_ReadStringLiteral( FileLexInfo& file_lex_info );
static Token Lexer_ReadCharLiteral( FileLexInfo& file_lex_info );
static Token Lexer_ReadDirective( FileLexInfo& file_lex_info );
static Token Lexer_ReadIdentifier( FileLexInfo& file_lex_info );


#define LEX_SINGLE_CHAR_TOK( token_kind ) \
	{                                                     \
		Token tk;                                         \
		tk.kind = token_kind;                             \
		tk.span = Span {                                  \
			.file_id = file_lex_info.file_id,             \
			.start   = file_lex_info.cursor_position,     \
			.end     = file_lex_info.cursor_position + 1, \
			.line    = file_lex_info.line_position,       \
		};                                                \
		file_lex_info.cursor_position++;                  \
		return tk;                                        \
	}

#define LEX_BASE_ASSIGN_FORM_TOK( base_kind, assign_kind ) \
	{                                                         \
		Token tk;                                             \
		tk.kind = base_kind;                                  \
		if ( *( read_head + 1 ) == '=' )                      \
		{                                                     \
			tk.kind = assign_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else                                                  \
		{                                                     \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 1, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position++;                  \
		}                                                     \
		return tk;                                            \
	}

#define LEX_BASE_DOUBLE_FORM_TOK( base_kind, double_char, double_kind ) \
	{                                                         \
		Token tk;                                             \
		tk.kind = base_kind;                                  \
		if ( *( read_head + 1 ) == double_char )              \
		{                                                     \
			tk.kind = double_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else                                                  \
		{                                                     \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 1, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position++;                  \
		}                                                     \
		return tk;                                            \
	}

#define LEX_BASE_DOUBLE_EXTRA_FORM_TOK( base_kind, double_char, double_kind, extra_char, extra_kind ) \
	{                                                         \
		Token tk;                                             \
		tk.kind = base_kind;                                  \
		if ( *( read_head + 1 ) == double_char )              \
		{                                                     \
			tk.kind = double_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else if ( *( read_head + 1 ) == extra_char )          \
		{                                                     \
			tk.kind = extra_kind;                             \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else                                                  \
		{                                                     \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 1, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position++;                  \
		}                                                     \
		return tk;                                            \
	}

#define LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( base_kind, double_char, double_kind, assign_kind ) \
	{                                                         \
		Token tk;                                             \
		tk.kind = base_kind;                                  \
		if ( *( read_head + 1 ) == double_char )              \
		{                                                     \
			tk.kind = double_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else if ( *( read_head + 1 ) == '=' )                 \
		{                                                     \
			tk.kind = assign_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else                                                  \
		{                                                     \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 1, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position++;                  \
		}                                                     \
		return tk;                                            \
	}

#define LEX_BASE_DOUBLE_ASSIGN_EXTRA_FORM_TOK( base_kind, double_char, double_kind, assign_kind, extra_char, extra_kind ) \
	{                                                         \
		Token tk;                                             \
		tk.kind = base_kind;                                  \
		if ( *( read_head + 1 ) == double_char )              \
		{                                                     \
			tk.kind = double_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else if ( *( read_head + 1 ) == '=' )                 \
		{                                                     \
			tk.kind = assign_kind;                            \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else if ( *( read_head + 1 ) == extra_char )          \
		{                                                     \
			tk.kind = extra_kind;                             \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 2, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position += 2;               \
		}                                                     \
		else                                                  \
		{                                                     \
			tk.span = Span {                                  \
				.file_id = file_lex_info.file_id,             \
				.start   = file_lex_info.cursor_position,     \
				.end     = file_lex_info.cursor_position + 1, \
				.line    = file_lex_info.line_position,       \
			};                                                \
			file_lex_info.cursor_position++;                  \
		}                                                     \
		return tk;                                            \
	}


Token Lexer_GetNextToken( FileLexInfo& file_lex_info )
{
	TIME_PROC();

	Lexer_SkipWhitespace( file_lex_info );

	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	switch ( *read_head )
	{
		case '\n':
		{
			Token tk;
			tk.kind = TK::EndOfLine;
			tk.span = Span {
				.file_id = file_lex_info.file_id,
				.start   = file_lex_info.cursor_position,
				.end     = file_lex_info.cursor_position + 1,
				.line    = file_lex_info.line_position,
			};

			file_lex_info.cursor_position++;
			file_lex_info.line_position++;

			return tk;
		}

		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
		case '8':
		case '9': return Lexer_ReadNumberLiteral( file_lex_info );

		case '[': LEX_SINGLE_CHAR_TOK( TK::LSquare );
		case ']': LEX_SINGLE_CHAR_TOK( TK::RSquare );
		case '{': LEX_SINGLE_CHAR_TOK( TK::LCurly );
		case '}': LEX_SINGLE_CHAR_TOK( TK::RCurly );
		case '(': LEX_SINGLE_CHAR_TOK( TK::LParen );
		case ')': LEX_SINGLE_CHAR_TOK( TK::RParen );

		case '!': LEX_BASE_ASSIGN_FORM_TOK( TK::Bang, TK::NEQ );

		case '$': LEX_SINGLE_CHAR_TOK( TK::Dollar );

		case '%': LEX_BASE_ASSIGN_FORM_TOK( TK::Percent, TK::PercentAssign );
		case '^': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::Caret, '^', TK::XOR, TK::CaretAssign );
		case '&': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::Ampersand, '&', TK::AND, TK::AmpersandAssign );
		case '*': LEX_BASE_ASSIGN_FORM_TOK( TK::Star, TK::StarAssign );
		case '-': LEX_BASE_DOUBLE_ASSIGN_EXTRA_FORM_TOK( TK::Minus, '-', TK::MinusMinus, TK::MinusAssign, '>', TK::ThinArrow );
		case '+': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::Plus, '+', TK::PlusPlus, TK::PlusAssign );
		case '=': LEX_BASE_DOUBLE_EXTRA_FORM_TOK( TK::Assign, '=', TK::EQ, '>', TK::ThiccArrow );
		case '|': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::Pipe, '|', TK::OR, TK::PipeAssign );
		case ';': LEX_SINGLE_CHAR_TOK( TK::Semicolon );
		case ':': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::Colon, ':', TK::DoubleColon, TK::ColonAssign );
		case ',': LEX_SINGLE_CHAR_TOK( TK::Comma );
		case '.': LEX_BASE_DOUBLE_FORM_TOK( TK::Dot, '.', TK::DotDot );
		case '<': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::LAngle, '<', TK::LShift, TK::LEQ );
		case '>': LEX_BASE_DOUBLE_ASSIGN_FORM_TOK( TK::RAngle, '>', TK::RShift, TK::GEQ );
		case '/':
		{
			if ( *( read_head + 1 ) == '/' )
			{
				while ( *read_head != '\n' )
				{
					read_head++;
					file_lex_info.cursor_position++;
				}

				return Lexer_GetNextToken( file_lex_info );
			}
			else if ( *( read_head + 1 ) == '*' )
			{
				read_head++;
				file_lex_info.cursor_position++;

				bool   escaped    = false;
				size_t nest_level = 1;

				while ( *read_head )
				{
					char c = *read_head;
					if ( c == '/' )
					{
						if ( *( read_head - 1 ) == '*' )
						{
							nest_level--;
							read_head++;
							file_lex_info.cursor_position++;
						}
						else if ( *( read_head + 1 ) == '*')
						{
							nest_level++;
							read_head += 2;
							file_lex_info.cursor_position += 2;
						}
						else
						{
							read_head++;
							file_lex_info.cursor_position++;
						}
					}
					else
					{
						if ( c == '\n' )
						{
							file_lex_info.line_position++;
						}

						read_head++;
						file_lex_info.cursor_position++;
					}

					if ( nest_level == 0 ) {
						escaped = true;
						break;
					}
				}

				DF_ASSERT( escaped, "Unterminated block comment" );

				return Lexer_GetNextToken( file_lex_info );
			}

			Token tk;
			tk.kind = TK::Slash;
			if ( *( read_head + 1 ) == '=' )
			{
				tk.kind = TK::SlashAssign;
				tk.span = Span {
					.file_id = file_lex_info.file_id,
					.start   = file_lex_info.cursor_position,
					.end     = file_lex_info.cursor_position + 2,
					.line    = file_lex_info.line_position,
				};
				file_lex_info.cursor_position += 2;
			}
			else
			{
				tk.span = Span {
					.file_id = file_lex_info.file_id,
					.start   = file_lex_info.cursor_position,
					.end     = file_lex_info.cursor_position + 1,
					.line    = file_lex_info.line_position,
				};
				file_lex_info.cursor_position++;
			}

			return tk;
		}

		case '"':  return Lexer_ReadStringLiteral( file_lex_info );
		case '\'': return Lexer_ReadCharLiteral( file_lex_info );

		case '#': return Lexer_ReadDirective( file_lex_info );

		case '\0': break;

		default: return Lexer_ReadIdentifier( file_lex_info );
	}

	Token tk;
	tk.kind = TK::EndOfFile;

	return tk;
}


static bool Lexer_IsDigit( char c )
{
	return ( c >= '0' && c <= '9' )
	    || ( c >= 'a' && c <= 'f' )
	    || ( c >= 'A' && c <= 'F' );
}

static uint64_t Lexer_CharToDigit( char c )
{
	if ( c >= '0' && c <= '9' )      return (uint64_t)( c - '0' );
	else if ( c >= 'a' && c <= 'f' ) return (uint64_t)( ( c - 'a' ) + 0xa );
	else if ( c >= 'A' && c <= 'F' ) return (uint64_t)( ( c - 'A' ) + 0xa );
	else                             return 0;
}

static Token Lexer_ReadNumberLiteral( FileLexInfo& file_lex_info )
{
	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	size_t   num_tok_start    = file_lex_info.cursor_position;
	bool     is_float         = false;
	uint64_t int_value        = 0;
	uint64_t fractional_value = 0;
	double   float_value      = 0.0;
	uint8_t  literal_base     = 10;

	if ( *read_head == '0' )
	{
		// Handle potential alternate-base literals
		switch ( *( read_head + 1 ) )
		{
			case 'b': // binary literal '0b01000001'
			{
				literal_base = 2;
				read_head += 2;
				file_lex_info.cursor_position += 2;
				break;
			}
			case 'o': // octal literal '0o777'
			{
				literal_base = 8;
				read_head += 2;
				file_lex_info.cursor_position += 2;
				break;
			}
			case 'x': // hex literal '0xdeadc0de'
			{
				literal_base = 16;
				read_head += 2;
				file_lex_info.cursor_position += 2;
				break;
			}
			default:  literal_base = 10;
		}
	}

	while ( *read_head && Lexer_IsDigit( *read_head ) )
	{
		uint64_t digit = Lexer_CharToDigit( *read_head );

		DF_ASSERT( digit < (uint64_t)literal_base, "Digit '%d', is not in base '%d'", (int)digit, (int)literal_base );

		int_value *= literal_base;
		int_value += digit;

		read_head++;
		file_lex_info.cursor_position++;
	}

	if ( *read_head == '.' )
	{
		// Make sure we don't accidentally interpret a '..' as a '.'
		if ( *( read_head + 1 ) != '.' )
		{
			DF_ASSERT( literal_base == 10, "Floating point literals must be in base 10" );

			is_float = true;
			read_head++;
			file_lex_info.cursor_position++;
		}
	}

	if ( is_float )
	{
		int place = 1;
		while ( *read_head && Lexer_IsDigit( *read_head ) )
		{
			uint64_t digit = Lexer_CharToDigit( *read_head );

			fractional_value *= 10;
			fractional_value += digit;

			read_head++;
			file_lex_info.cursor_position++;
			place *= 10;
		}

		float_value = (double)int_value;
		float_value += (double)fractional_value / (double)place;
	}

	Number num_tok;
	if ( is_float )
	{
		num_tok.kind = NumKind::FloatingPoint;
		num_tok.fnum = float_value;
	}
	else
	{
		num_tok.kind = NumKind::Integer;
		num_tok.inum = int_value;
	}

	Token tk;
	tk.kind = TK::Number;
	tk.span = {
		.file_id = file_lex_info.file_id,
		.start   = num_tok_start,
		.end     = file_lex_info.cursor_position,
		.line    = file_lex_info.line_position,
	};
	tk.number = num_tok;

	return tk;
}


static Token Lexer_ReadStringLiteral( FileLexInfo& file_lex_info )
{
	size_t str_lit_tok_start = file_lex_info.cursor_position;
	file_lex_info.cursor_position++;

	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	std::string literal;
	while ( *read_head != '"' )
	{
		DF_ASSERT( *read_head != '\n', "Got unterminated string literal" );

		char c = *read_head;
		if ( c == '\\' )
		{
			switch ( *( read_head + 1 ) )
			{
				case 'a': literal.push_back( '\n' ); break;
				case 'b': literal.push_back( '\b' ); break;
				case 'e': literal.push_back( '\x1b' ); break;
				case 'f': literal.push_back( '\f' ); break;
				case 'n': literal.push_back( '\n' ); break;
				case 'r': literal.push_back( '\r' ); break;
				case 't': literal.push_back( '\t' ); break;
				case 'v': literal.push_back( '\v' ); break;
				default:  literal.push_back( *( read_head + 1 ) );
			}

			read_head += 2;
			file_lex_info.cursor_position += 2;

			continue;
		}

		literal.push_back( c );

		read_head++;
		file_lex_info.cursor_position++;
	}

	// Set the cursor to just after the terminating '"'
	file_lex_info.cursor_position++;

	Token tk;
	tk.kind = TK::StringLiteral;
	tk.span = Span {
		.file_id = file_lex_info.file_id,
		.start   = str_lit_tok_start,
		.end     = file_lex_info.cursor_position,
		.line    = file_lex_info.line_position,
	};
	tk.str = std::move( literal );

	return tk;
}


static Token Lexer_ReadCharLiteral( FileLexInfo& file_lex_info )
{
	size_t char_lit_tok_start = file_lex_info.cursor_position++;

	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	char literal = '\0';

	if ( *read_head == '\\' )
	{
		switch ( *( read_head + 1 ) )
		{
			case 'a': literal = '\a'; break;
			case 'b': literal = '\b'; break;
			case 'e': literal = '\x1b'; break;
			case 'f': literal = '\f'; break;
			case 'n': literal = '\n'; break;
			case 'r': literal = '\r'; break;
			case 't': literal = '\t'; break;
			case 'v': literal = '\v'; break;
			default:  literal = *( read_head + 1 );
		}

		read_head++;
		file_lex_info.cursor_position++;
	}
	else
	{
		literal = *read_head;
	}

	read_head++;
	file_lex_info.cursor_position++;

	DF_ASSERT( *read_head == '\'', "Unterminated character literal. expected ''', got: '%c'", *read_head );

	// Set the cursor to just after the last '''
	file_lex_info.cursor_position++;

	Token tk;
	tk.kind = TK::CharLiteral;
	tk.span = Span {
		.file_id = file_lex_info.file_id,
		.start   = char_lit_tok_start,
		.end     = file_lex_info.cursor_position,
		.line    = file_lex_info.line_position,
	};
	tk.char_lit = literal;

	return tk;
}


bool Lexer_IsIdentChar( char c )
{
	return ( c >= 'A' && c <= 'Z' )
	    || ( c >= 'a' && c <= 'z' )
	    || ( c == '_' )
	    || Lexer_IsDigit( c );
}


static std::unordered_map<std::string, TokenKind> s_directive_type_map = {
	{ "load", TK::DirectiveLoad },
};


static Token Lexer_ReadDirective( FileLexInfo& file_lex_info )
{
	size_t directive_tok_start = file_lex_info.cursor_position;
	file_lex_info.cursor_position++;

	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	std::string directive_name;
	while ( Lexer_IsIdentChar( *read_head ) )
	{
		directive_name.push_back( *read_head );

		read_head++;
		file_lex_info.cursor_position++;
	}

	Span directive_span = {
		.file_id = file_lex_info.file_id,
		.start   = directive_tok_start,
		.end     = file_lex_info.cursor_position,
		.line    = file_lex_info.line_position,
	};

	auto find_iter = s_directive_type_map.find( directive_name );
	if ( find_iter == s_directive_type_map.cend() )
	{
		log_span_fatal( directive_span, "Unknown compile-time directive '%s'", directive_name.c_str() );
	}

	Token tk;
	tk.kind = s_directive_type_map.at( directive_name );
	tk.span = directive_span;

	return tk;
}


static std::unordered_map<std::string, TokenKind> s_keyword_type_map = {
	{ "true",     TK::KeywordTrue      },
	{ "false",    TK::KeywordFalse     },
	{ "decl",     TK::KeywordDecl      },
	{ "let",      TK::KeywordLet       },
	{ "if",       TK::KeywordIf        },
	{ "else",     TK::KeywordElse      },
	{ "for",      TK::KeywordFor       },
	{ "while",    TK::KeywordWhile     },
	{ "loop",     TK::KeywordLoop      },
	{ "continue", TK::KeywordContinue  },
	{ "break",    TK::KeywordBreak     },
	{ "return",   TK::KeywordReturn    },
	{ "in",       TK::KeywordIn        },
	{ "as",       TK::KeywordAs        },
	{ "struct",   TK::KeywordStruct    },
	{ "enum",     TK::KeywordEnum      },
	{ "union",    TK::KeywordUnion     },
	{ "nothing",  TK::PrimitiveNothing },
	{ "bool",     TK::PrimitiveBool    },
	{ "char",     TK::PrimitiveChar    },
	{ "ubyte",    TK::PrimitiveU8      },
	{ "ibyte",    TK::PrimitiveI8      },
	{ "uword",    TK::PrimitiveU16     },
	{ "iword",    TK::PrimitiveI16     },
	{ "ulong",    TK::PrimitiveU32     },
	{ "ilong",    TK::PrimitiveI32     },
	{ "uquad",    TK::PrimitiveU64     },
	{ "iquad",    TK::PrimitiveI64     },
	{ "flong",    TK::PrimitiveF32     },
	{ "fquad",    TK::PrimitiveF64     },
	{ "rawptr",   TK::PrimitiveRawPtr  },
	{ "string",   TK::PrimitiveString  },
	{ "cstring",  TK::PrimitiveCString },
};


static Token Lexer_ReadIdentifier( FileLexInfo& file_lex_info )
{
	size_t ident_tok_start = file_lex_info.cursor_position;
	char const* read_head = file_lex_info.raw_file_data + file_lex_info.cursor_position;

	std::string ident;
	while ( Lexer_IsIdentChar( *read_head ) )
	{
		ident.push_back( *read_head );

		read_head++;
		file_lex_info.cursor_position++;
	}

	Span ident_span = {
		.file_id = file_lex_info.file_id,
		.start   = ident_tok_start,
		.end     = file_lex_info.cursor_position,
		.line    = file_lex_info.line_position,
	};

	Token tk;
	tk.span = ident_span;

	auto find_iter = s_keyword_type_map.find( ident );
	if ( find_iter != s_keyword_type_map.cend() )
	{
		tk.kind = find_iter->second;
	}
	else
	{
		tk.kind = TK::Ident;
		tk.str  = ident;
	}

	return tk;
}
