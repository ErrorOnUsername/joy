#pragma once

#include "array.hh"
#include "token.hh"
#include "operators.hh"

using NodeKind = uint16_t;
namespace AstNodeKind
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

struct AstNode {
	NodeKind kind = AstNodeKind::Invalid;
	Span     span;
	Type     type;
};


//
// Lexical Scopes
//
using ScopeID = int64_t;
struct Scope {
	ScopeID parent_id;

	// TODO: data lookup tables...

	Array<AstNode*> statement_list;
};


//
// Literal Types
//

struct IntegerLiteralExpr : public AstNode {
	bool     is_signed_int = false;
	uint64_t data          = 0xdeadbeefdeadbeef;
};

struct FloatingPointLiteralExpr : public AstNode {
	double value = 0.0;
};

struct StringLiteralExpr : public AstNode {
	std::string value;
};

struct CharacterLiteralExpr : public AstNode {
	int32_t codepoint = '$';
};

//
// Binary Operation
//

struct BinaryOperationExpr : public AstNode {
	BinOpKind kind = BinaryOpKind::Invalid;

	AstNode* lhs = nullptr;
	AstNode* rhs = nullptr;
};

//
// Unary Operation
//

struct UnaryOperationExpr : public AstNode {
	UnOpKind kind = UnaryOpKind::Invalid;

	AstNode* operand = nullptr;
};


//
// Module
//
struct Module {
	Array<Scope> scopes;
};
