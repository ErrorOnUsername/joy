#pragma once
#include <cstdint>
#include <string>

enum TokenKind {
	TK_INVAL,

	TK_EOF,
	TK_EOL,

	TK_L_SQUARE,
	TK_R_SQUARE,
	TK_L_CURLY,
	TK_R_CURLY,
	TK_L_PAREN,
	TK_R_PAREN,

	TK_BANG,
	TK_NEQ,

	TK_DOLLAR,

	TK_PERCENT,
	TK_PERCENT_ASSIGN,

	TK_CARET,
	TK_XOR,
	TK_CARET_ASSIGN,

	TK_AMPERSAND,
	TK_AND,
	TK_AMPERSAND_ASSIGN,

	TK_STAR,
	TK_STAR_ASSIGN,

	TK_MINUS,
	TK_MINUS_MINUS,
	TK_MINUS_ASSIGN,
	TK_THIN_ARROW,

	TK_PLUS,
	TK_PLUS_PLUS,
	TK_PLUS_ASSIGN,

	TK_ASSIGN,
	TK_EQ,
	TK_THICC_ARROW,

	TK_PIPE,
	TK_OR,
	TK_PIPE_ASSIGN,

	TK_SEMICOLON,

	TK_COLON,
	TK_DOUBLE_COLON,
	TK_COLON_ASSIGN,

	TK_COMMA,

	TK_DOT,
	TK_DOT_DOT,

	TK_L_ANGLE,
	TK_LEQ,

	TK_R_ANGLE,
	TK_GEQ,

	TK_SLASH,
	TK_SLASH_ASSIGN,

	TK_IDENT,
	TK_NUMBER,
	TK_STR_LIT,
	TK_CHAR_LIT,
	TK_BOOL_T,
	TK_BOOL_F,

	TK_CD_LOAD,

	TK_KW_DECL,
	TK_KW_LET,
	TK_KW_IF,
	TK_KW_ELSE,
	TK_KW_FOR,
	TK_KW_WHILE,
	TK_KW_LOOP,
	TK_KW_CONTINUE,
	TK_KW_BREAK,
	TK_KW_RETURN,
	TK_KW_IN,
	TK_KW_AS,
	TK_KW_STRUCT,
	TK_KW_ENUM,
	TK_KW_UNION,

	TK_TY_NOTHING,
	TK_TY_CHAR,
	TK_TY_BOOL,
	TK_TY_U8,
	TK_TY_I8,
	TK_TY_U16,
	TK_TY_I16,
	TK_TY_U32,
	TK_TY_I32,
	TK_TY_U64,
	TK_TY_I64,
	TK_TY_F32,
	TK_TY_F64,
	TK_TY_RAWPTR,
	TK_TY_STR,
};

enum NumberKind {
	NK_INT,
	NK_UINT,
	NK_FLOAT,
};

struct Number {
	NumberKind kind;
	union {
		int64_t sint;
		uint64_t uint;
		double floating_point;
	};
};

struct Span {
	size_t file_id;
	int64_t start_idx;
	int64_t end_idx;
	int64_t line;
};

struct Token {
	TokenKind kind;
	Span span;
	Number number;
	std::string str;

	Token(size_t file_id, TokenKind kind, int64_t start_idx, int64_t start_line)
		: kind(kind)
		, span({ file_id, start_idx, -1, start_line })
		, number()
		, str()
	{ }
};

enum BinOpKind : uint32_t;

char const* tk_as_str(TokenKind kind);
BinOpKind tk_as_operator(TokenKind kind);
bool is_tk_operator(TokenKind kind);
