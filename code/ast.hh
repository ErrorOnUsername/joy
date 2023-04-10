#pragma once

#include "token.hh"

using ExprKind = uint16_t;
namespace ExpressionKind
{
	enum {
		Invalid,
		IntegerLiteral,
		FloatingPointLiteral,
		StringLiteral,
		CharacterLiteral,
		BinaryOperation,
		UnaryOperation,
	};
}

struct Type { int dummy; };

struct Expr {
	ExprKind kind = ExpressionKind::Invalid;
	Span     span;
	Type     type;
};

//
// Literal Types
//

struct IntegerLiteralExpr : public Expr {
	bool     is_signed_int = false;
	uint64_t data = 0xdeadbeefdeadbeef;
};

struct FloatingPointLiteralExpr : public Expr {
	double value = 0.0;
};

struct StringLiteralExpr : public Expr {
	std::string value;
};

struct CharacterLiteralExpr : public Expr {
	int32_t codepoint = '$';
};

//
// Binary Operation
//

using BinOpKind = uint16_t;
namespace BinaryOpKind
{
	enum {
		Invalid,
		Add,
		Subtract,
		Multiply,
		Divide,
		Modulo,
		LogicalAnd,
		BitwiseAnd,
		LogicalOr,
		BitwiseOr,
		LogicalXor,
		BitwiseXor,
		MemberAccess,
		Range,
	};
}

struct BinaryOperationExpr : public Expr {
	BinOpKind kind = BinaryOpKind::Invalid;

	Expr* lhs = nullptr;
	Expr* rhs = nullptr;
};

//
// Unary Operation
//

using UnOpKind = uint16_t;
namespace UnaryOpKind
{
	enum {
		Invalid,
		LogicalNot,
		BitwiseNot,
		Negate,
		Dereference,
		AddressOf,
	};
}

struct UnaryOperationExpr : public Expr {
	UnOpKind kind = UnaryOpKind::Invalid;

	Expr* operand = nullptr;
};
