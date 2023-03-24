#pragma once
#include <vector>
#include <unordered_map>
#include <unordered_set>

#include "arena.hh"
#include "token.hh"
#include "type.hh"

using ScopeID = int64_t;
using VarID   = int64_t;

enum ExprKind {
	EXPR_BOOL,
	EXPR_NUMBER,
	EXPR_STRING,
	EXPR_CHAR,
	EXPR_VAR,
	EXPR_RANGE,
	EXPR_PROC_CALL,
	EXPR_BIN_OP,
	EXPR_UNARY_OP,
};

struct Expr {
	Span span;
	ExprKind kind;
	TypeID result_ty;
};

struct ConstBoolExpr : public Expr {
	bool value;
};

struct ConstNumberExpr : public Expr {
	Number num;
};

struct ConstStringExpr : public Expr {
	std::string str; // FIXME: Use an id (index into per-module string literal store) to store (std::string is just too big) possibly indirected through a hashmap (to cut down on duplicates)
};

struct ConstCharExpr : public Expr {
	uint64_t codepoint; // Smallest size that will hold the largest UTF-8 codepoint
};

struct VarExpr : public Expr {
	std::string name;
	VarID var_id;
};

struct RangeExpr : public Expr {
	bool is_left_included;
	Expr* lhs;
	Expr* rhs;
	bool is_right_included;
};

struct ProcCallExpr : public Expr {
	std::string name;
	std::vector<Expr*> params;
};

void dump_expr(Expr* expr, size_t indent_level);

enum BinOpKind : uint32_t {
	B_OP_INVAL,

	B_OP_MEMBER_ACCESS,
	B_OP_RANGE,

	B_OP_ADD,
	B_OP_SUB,
	B_OP_MUL,
	B_OP_DIV,
	B_OP_MOD,

	B_OP_L_AND,
	B_OP_B_AND,
	B_OP_L_OR,
	B_OP_B_OR,
	B_OP_L_XOR,
	B_OP_B_XOR,

	B_OP_EQ,
	B_OP_NEQ,
	B_OP_LT,
	B_OP_LEQ,
	B_OP_GT,
	B_OP_GEQ,

	B_OP_ADD_ASSIGN,
	B_OP_SUB_ASSIGN,
	B_OP_MUL_ASSIGN,
	B_OP_DIV_ASSIGN,
	B_OP_MOD_ASSIGN,
	B_OP_AND_ASSIGN,
	B_OP_OR_ASSIGN,
	B_OP_XOR_ASSIGN,
	B_OP_ASSIGN,
};

bool is_assign_op(BinOpKind kind);
int64_t op_priority(BinOpKind kind);
char const* bin_op_as_str(BinOpKind kind);

struct BinOpExpr : public Expr {
	BinOpKind op_kind;
	Expr* lhs;
	Expr* rhs;
};

enum UnaryOpKind {
	U_OP_NEG,

	U_OP_PRE_INC,
	U_OP_PRE_DEC,
	U_OP_POST_INC,
	U_OP_POST_DEC,

	U_OP_ADDR_OF,
	U_OP_DEREF,

	U_OP_L_NOT,

	U_OP_CAST,
};

struct UnaryOpExpr : public Expr {
	UnaryOpKind op_kind;
	Expr* operand;
	TypeID to_type; // for U_OP_CAST
};

enum StmntKind {
	STMNT_CONST_DECL,
	STMNT_STRUCT_DECL,
	STMNT_ENUM_DECL,
	STMNT_PROC_DECL,
	STMNT_VAR_DECL,
	STMNT_IF,
	STMNT_FOR,
	STMNT_WHILE,
	STMNT_LOOP,
	STMNT_CONTINUE,
	STMNT_BREAK,
	STMNT_RETURN,
	STMNT_BLOCK,
	STMNT_EXPR,
};

struct Stmnt {
	Span span;
	StmntKind kind;
};

struct ConstDeclStmnt : public Stmnt {
	std::string name;
	Expr* const_val;
};

struct StructMember {
	std::string name;
	TypeID type;
};

struct StructDeclStmnt : public Stmnt {
	std::string name;
	std::vector<StructMember> members;
};

struct EnumVariant {
	std::string name;
	Expr* val;
};

struct EnumDeclStmnt : public Stmnt {
	std::vector<EnumVariant> variants;
};

struct ProcParameter {
	std::string name;
	VarID var_id;
	TypeID type;
	Expr* default_value;
};

struct Block {
	ScopeID scope_id;
	std::vector<Stmnt*> stmnts;
};

enum ProcLinkage {
	PROC_LINKAGE_INTERNAL,
	PROC_LINKAGE_EXTERNAL,
};

struct ProcDeclStmnt : public Stmnt {
	std::string name;
	std::vector<ProcParameter> params;
	Block body;
	ProcLinkage linkage;
	std::string linking_lib_name;
};

struct VarDeclStmnt : public Stmnt {
	ScopeID scope_id;
	std::string name;
	TypeID type;
	Expr* default_value;
};

struct IfStmnt : public Stmnt {
	Expr* condition;
	Block body;
	Stmnt* else_chain;
};

struct ForLoopIterator {
	std::string name;
	VarID var_id;
};

struct ForLoopStmnt : public Stmnt {
	ForLoopIterator it;
	RangeExpr* range;
	Block body;
};

struct WhileLoopStmnt : public Stmnt {
	Expr* condition;
	Block body;
};

struct LoopStmnt : public Stmnt {
	Block body;
};

struct ReturnStmnt : public Stmnt {
	Expr* val;
};

struct BlockStmnt : public Stmnt {
	Block block;
};

struct ExprStmnt : public Stmnt {
	Expr* expr;
};

struct Scope {
	ScopeID parent;
	std::unordered_map<std::string, VarID> vars_id_map;
};

using ModuleID = int64_t;

struct Module {
	std::string directory;

	Arena stmnt_arena;
	Arena expr_arena;

	std::unordered_set<Module*> imports;
	std::unordered_map<std::string, size_t> type_id_map;
	std::vector<Scope> scopes;
	std::vector<Type> types;
	std::vector<VarDeclStmnt> vars;
	std::vector<StructDeclStmnt> structs;
	std::vector<ProcDeclStmnt> procs;
};
