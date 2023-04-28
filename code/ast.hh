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
		StructDecl,
		StructMemberDecl,
		EnumDecl,
	};
}

namespace AstNodeFlag
{
	enum {
		None = 0,
		Decl = ( 1 << 0 ),
		NumberLiteral = ( 1 << 1 ),
	};
}

struct Type;

struct AstNode {
	NodeKind kind = AstNodeKind::Invalid;
	Span     span;
	Type*    type;
	uint64_t flags = AstNodeFlag::None;
};


//
// Types
//

using TyKind = uint16_t;
namespace TypeKind
{
	enum {
		Invalid,
		Pointer,
		Array,
		NamedUnknown,
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

struct Type {
	TyKind      kind;
	Span        span;
	std::string name;
	std::string import_alias;
	Type*       underlying; // for pointers and arrays
	AstNode*    size_expr; // for arrays
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
// Statements
//
struct VarDeclStmnt : public AstNode {
	std::string name;
	AstNode*    default_value;
};

struct StructDeclStmnt : public AstNode {
	std::string          name;
	Array<VarDeclStmnt*> members;
};

struct EnumVariant {
	Span                span;
	std::string         name;
	IntegerLiteralExpr* val;
};

struct EnumDeclStmnt : public AstNode {
	std::string        name;
	Array<EnumVariant> variants;
};


//
// Module
//
struct Module {
	Array<Scope> scopes;
};
