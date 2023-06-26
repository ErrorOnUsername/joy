#pragma once

#include "array.hh"
#include "arena.hh"
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
		Range,
		UnaryOperation,
		VarDecl,
		StructDecl,
		EnumDecl,
		UnionDecl,
		UnionVariantMember,
		ProcDecl,
		IfStmnt,
		VarRef,
		ProcCall,
		LexicalBlock,
		ForLoop,
		WhileLoop,
		InfiniteLoop,
		ContinueStmnt,
		BreakStmnt,
		ReturnStmnt,
		LoadStmnt,
	};
}

namespace AstNodeFlag
{
	enum {
		None = 0,

		Decl                 = ( 1 << 0 ),
		IntegerLiteral       = ( 1 << 1 ),
		FloatingPointLiteral = ( 1 << 2 ),
		StringLiteral        = ( 1 << 3 ),

		NumberLiteral = IntegerLiteral | FloatingPointLiteral,
		Constant      = NumberLiteral | StringLiteral,
	};
}


using TypeID = int64_t;
namespace ReservedTypeID
{
	enum {
		Unknown = -1,

		PrimitiveNothing = -2,
		PrimitiveBool    = -3,
		PrimitiveChar    = -4,
		PrimitiveU8      = -5,
		PrimitiveI8      = -6,
		PrimitiveU16     = -7,
		PrimitiveI16     = -8,
		PrimitiveU32     = -9,
		PrimitiveI32     = -10,
		PrimitiveU64     = -11,
		PrimitiveI64     = -12,
		PrimitiveF32     = -13,
		PrimitiveF64     = -14,
		PrimitiveRawPtr  = -15,
		PrimitiveString  = -16,
		PrimitiveCString = -17,
	};
}

struct Type;

struct AstNode {
	NodeKind kind = AstNodeKind::Invalid;
	Span     span;
	Type*    type  = nullptr;
	TypeID   type_id = ReservedTypeID::Unknown;
	uint64_t flags = AstNodeFlag::None;
};


//
// Types
//

using TyKind = uint32_t;
namespace TypeKind
{
	enum {
		Invalid      = 0,
		Pointer      = ( 1 << 0 ),
		Array        = ( 1 << 1 ),
		NamedUnknown = ( 1 << 2 ),

		PrimitiveNothing = ( 1 << 3 ),
		PrimitiveBool    = ( 1 << 4 ),
		PrimitiveChar    = ( 1 << 5 ),
		PrimitiveU8      = ( 1 << 6 ),
		PrimitiveI8      = ( 1 << 7 ),
		PrimitiveU16     = ( 1 << 8 ),
		PrimitiveI16     = ( 1 << 9 ),
		PrimitiveU32     = ( 1 << 10 ),
		PrimitiveI32     = ( 1 << 11 ),
		PrimitiveU64     = ( 1 << 12 ),
		PrimitiveI64     = ( 1 << 13 ),
		PrimitiveUSize   = ( 1 << 14 ),
		PrimitiveISize   = ( 1 << 15 ),
		PrimitiveF32     = ( 1 << 16 ),
		PrimitiveF64     = ( 1 << 17 ),
		PrimitiveRawPtr  = ( 1 << 18 ),
		PrimitiveString  = ( 1 << 19 ),
		PrimitiveCString = ( 1 << 20 ),

		Primitive = PrimitiveNothing
		          | PrimitiveBool
		          | PrimitiveChar
		          | PrimitiveU8
		          | PrimitiveI8
		          | PrimitiveU16
		          | PrimitiveI16
		          | PrimitiveU32
		          | PrimitiveI32
		          | PrimitiveU64
		          | PrimitiveI64
		          | PrimitiveF32
		          | PrimitiveF64
	              | PrimitiveRawPtr
		          | PrimitiveString
		          | PrimitiveCString,
	};
}

struct Type {
	TyKind      kind;
	Span        span;
	TypeID      id;
	std::string name;
	std::string import_alias;
	Type*       underlying; // for pointers and arrays
	AstNode*    size_expr; // for arrays
};


struct VarDeclStmnt;
struct ProcDeclStmnt;

//
// Lexical Scopes
//
struct Scope {
	Scope* parent = nullptr;

	// TODO: data lookup tables...

	Array<AstNode*>       types;
	Array<ProcDeclStmnt*> procedures;
	Array<AstNode*>       statements;
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
// Ref Expressions
//

struct VarRefExpr : public AstNode {
	Array<std::string> name_path;
};

struct ProcCallExpr : public AstNode {
	Array<std::string> name_path;
	Array<AstNode*> params;
};

//
// Binary Operation
//

struct BinaryOperationExpr : public AstNode {
	BinOpKind op_kind = BinaryOpKind::Invalid;

	AstNode* lhs = nullptr;
	AstNode* rhs = nullptr;
};

//
// Range Expression
//

struct RangeExpr : public AstNode {
	bool is_left_bound_included;
	bool is_right_bound_included;

	AstNode* lhs = nullptr;
	AstNode* rhs = nullptr;
};

//
// Unary Operation
//

struct UnaryOperationExpr : public AstNode {
	UnOpKind op_kind = UnaryOpKind::Invalid;

	AstNode* operand = nullptr;
};

//
// Statements
//
struct VarDeclStmnt : public AstNode {
	std::string name;
	AstNode*    default_value = nullptr;
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

struct UnionVariant {
	Span                 span;
	std::string          name;
	Array<VarDeclStmnt*> members;
};

struct UnionDeclStmnt : public AstNode {
	std::string         name;
	Array<UnionVariant> variants;
};

struct LexicalBlock : public AstNode {
	Scope* scope = nullptr;
};

struct ProcDeclStmnt : public AstNode {
	std::string          name;
	Array<VarDeclStmnt*> params;
	Array<Type*>         return_types; // TODO: Named return types?
	LexicalBlock*        body = nullptr;
};

struct IfStmnt : public AstNode {
	AstNode* condition_expr = nullptr;
	AstNode* then_block     = nullptr;
	IfStmnt* else_stmnt     = nullptr;
};

struct IterName {
	std::string name;
	Type*       type = nullptr;
};

struct ForLoopStmnt : public AstNode {
	IterName      iter;
	RangeExpr*    range = nullptr;
	LexicalBlock* body  = nullptr;
};

struct WhileLoopStmnt : public AstNode {
	AstNode*      condition_expr = nullptr;
	LexicalBlock* body           = nullptr;
};

struct InfiniteLoopStmnt : public AstNode {
	LexicalBlock* body = nullptr;
};

struct ReturnStmnt : public AstNode {
	AstNode* expr = nullptr;
};

struct Module;

struct LoadStmnt : public AstNode {
	Module* module = nullptr;
	std::string alias;
};


//
// Module
//
struct Module {
	std::string full_path;

	bool   typechecker_complete = false;
	size_t typechecker_task_group;

	Arena  scope_arena;
	Scope* root_scope;

	Arena node_arena;
	Arena type_arena;

	Array<LoadStmnt*> imports;

	Module()
		: scope_arena( 2 * 1024 )
		, root_scope( nullptr )
		, node_arena( 16 * 1024 )
		, type_arena( 16 * 1024 )
	{
	}
};
