#pragma once
#include <cstdint>
#include <string>

#include "file_manager.hh"

using TokenKind = uint16_t;

namespace TK
{
	enum : uint16_t {
		Invalid,

		EndOfFile,
		EndOfLine,

		LSquare,
		RSquare,
		LCurly,
		RCurly,
		LParen,
		RParen,

		Bang,
		NEQ,

		Dollar,

		Percent,
		PercentAssign,

		Caret,
		XOR,
		CaretAssign,

		Ampersand,
		AND,
		AmpersandAssign,

		Star,
		StarAssign,

		Minus,
		MinusMinus,
		MinusAssign,
		ThinArrow,

		Plus,
		PlusPlus,
		PlusAssign,

		Assign,
		EQ,
		ThiccArrow,

		Pipe,
		OR,
		PipeAssign,

		Tilde,
		TildeAssign,

		Semicolon,

		Colon,
		DoubleColon,
		ColonAssign,

		Comma,

		Dot,
		DotDot,

		LAngle,
		LShift,
		LEQ,

		RAngle,
		RShift,
		GEQ,

		Slash,
		SlashAssign,

		Ident,
		Number,
		StringLiteral,
		CharLiteral,

		DirectiveLoad,

		KeywordTrue,
		KeywordFalse,
		KeywordDecl,
		KeywordLet,
		KeywordIf,
		KeywordElse,
		KeywordFor,
		KeywordWhile,
		KeywordLoop,
		KeywordContinue,
		KeywordBreak,
		KeywordReturn,
		KeywordIn,
		KeywordAs,
		KeywordStruct,
		KeywordEnum,
		KeywordUnion,

		PrimitiveNothing,
		PrimitiveBool,
		PrimitiveChar,
		PrimitiveU8,
		PrimitiveI8,
		PrimitiveU16,
		PrimitiveI16,
		PrimitiveU32,
		PrimitiveI32,
		PrimitiveU64,
		PrimitiveI64,
		PrimitiveF32,
		PrimitiveF64,
		PrimitiveRawPtr,
		PrimitiveString,
		PrimitiveCString,
	};
}

struct Span {
	FileID file_id = -1;
	size_t start   = 0;
	size_t end     = 0;
	size_t line    = 0;
};

using NumberKind = uint8_t;

namespace NumKind
{
	enum : uint8_t {
		Integer,
		FloatingPoint,
	};
}

struct Number {
	NumberKind kind = NumKind::Integer;
	union {
		uint64_t inum;
		double   fnum;
	};
};

struct Token {
	TokenKind   kind = TK::Invalid;
	Span        span;
	Number      number;
	std::string str;
	char        char_lit;
};

char const* Token_GetKindAsString( TokenKind kind );
Span join_span( Span const& left, Span const& right );
