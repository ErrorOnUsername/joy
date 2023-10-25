package main

import "core:intrinsics"
import "core:mem"


PlatformFlags :: bit_set[Platform]
Platform :: enum
{
	Windows,
	Darwin,
	Linux,
}

Package :: struct
{
	shared_scope: ^Scope,
	modules:      [dynamic]^Module,
}

Module :: struct
{
	owning_pkg:     ^Package,
	platform_flags: PlatformFlags,
	private_scope:  ^Scope,
	imports:        [dynamic]^ImportStmnt,
}

Scope :: struct
{
	using node: Node,
	stmnts:      [dynamic]^Stmnt,
	parent:     ^Scope,
}



//
// Declarations
//

StructDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
	members:     [dynamic]^VarDecl,
}

EnumVariant :: struct
{
	using node: Node,
	name:       string,
}

EnumDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
	variants:    [dynamic]^EnumVariant,
}

UnionDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
}

ProcLinkage :: enum
{
	Internal,
	Foreign,
}

ProcDecl :: struct
{
	using stmnt:      Stmnt,
	name:             string,
	linkage:          ProcLinkage,
	foreign_lib_name: ^Ident,
	params:           [dynamic]^VarDecl,
	body:             ^Scope,
}

VarDecl :: struct
{
	using stmnt:   Stmnt,
	name:          string,
	default_value: ^Expr,
}

ForeignLibraryDecl :: struct
{
	using stmnt:       Stmnt,
	name:              string,
	is_system_library: bool,
	library_path:      string,
}



//
// Statements
//

ImportStmnt :: struct
{
	using stmnt: Stmnt,
}

ExprStmnt :: struct
{
	using stmnt: Stmnt,
	expr:        ^Expr,
}

BlockStmnt :: struct
{
	using stmnt: Stmnt,
	scope:       ^Scope,
}

ContinueStmnt :: struct
{
	using stmnt: Stmnt,
}

BreakStmnt :: struct
{
	using stmnt: Stmnt,
}

IfStmnt :: struct
{
	using stmnt: Stmnt,
	then_block:  ^Scope,
	else_stmnt:  ^IfStmnt,
}

ForLoop :: struct
{
	using stmnt: Stmnt,
	iter_ident: ^Ident,
	range:      ^Expr,
	body:       ^Scope,
}

WhileLoop :: struct
{
	using stmnt: Stmnt,
	cond:        ^Expr,
	body:        ^Scope,
}

InfiniteLoop :: struct
{
	using stmnt: Stmnt,
	body:        ^Scope,
}



//
// Expressions
//

Ident :: struct
{
	using expr: Expr,
	name:       string,
}

StringLiteralExpr :: struct
{
	using expr: Expr,
	str:        string,
}

NumberLiteralExpr :: struct
{
	using expr: Expr,
	str:        string,
}

RangeExpr :: struct
{
	using expr: Expr,
	left_bound_inclusive:  bool,
	right_bound_inclusive: bool,
	range_expr:            ^BinOpExpr,
}

BinaryOperator :: enum
{
	Invalid,

	MemberAccess,

	Add,
	Subtract,
	Multiply,
	Divide,
	Modulo,

	LessThanOrEq,
	LessThan,
	GreaterThanOrEq,
	GreaterThan,

	Equal,
	NotEqual,

	LogicalAnd,
	LogicalOr,
	LogicalXOr,
	BitwiseAnd,
	BitwiseOr,
	BitwiseXOr,

	BitwiseLShift,
	BitwiseRShift,

	Range,

	Assign,

	AddAssign,
	SubtractAssign,
	MultiplyAssign,
	DivideAssign,
	ModuloAssign,
	AndAssign,
	OrAssign,
	XOrAssign,
}

BinOpExpr :: struct
{
	using expr: Expr,
	op:         BinaryOperator,
	lhs:        ^Expr,
	rhs:        ^Expr,
}

bin_op_priority :: proc( op: BinaryOperator ) -> i8
{
	switch op {
		case .Invalid: return -1

		case .MemberAccess:
			return 14

		case .Multiply, .Divide, .Modulo:
			return 13

		case .Add, .Subtract:
			return 12

		case .BitwiseLShift, .BitwiseRShift:
			return 11

		case .LessThanOrEq, .LessThan,
		     .GreaterThanOrEq, .GreaterThan:
			return 10

		case .Equal, .NotEqual:
			return 9

		case .BitwiseAnd: return 8
		case .BitwiseOr:  return 7
		case .BitwiseXOr: return 6
		case .LogicalAnd: return 5
		case .LogicalOr:  return 4
		case .LogicalXOr: return 3

		case .Range: return 2

		case .Assign, .AddAssign,
			 .SubtractAssign, .MultiplyAssign,
			 .DivideAssign, .ModuloAssign,
			 .AndAssign, .OrAssign, .XOrAssign:
			return 1
	}

	return -1
}

ProcCallExpr :: struct
{
	using expr: Expr,
	name:       string,
	params:     [dynamic]^Expr,
}


AnyStmnt :: union
{
	^ImportStmnt,
	^StructDecl,
	^EnumDecl,
	^UnionDecl,
	^ProcDecl,
	^ForeignLibraryDecl,
	^VarDecl,
	^ExprStmnt,
	^BlockStmnt,
	^ContinueStmnt,
	^BreakStmnt,
	^IfStmnt,
	^ForLoop,
	^WhileLoop,
	^InfiniteLoop,
}

Stmnt :: struct
{
	using node:    Node,
	derived_stmnt: AnyStmnt,
}

AnyExpr :: union
{
	^Ident,
	^StringLiteralExpr,
	^NumberLiteralExpr,
	^RangeExpr,
	^BinOpExpr,
	^ProcCallExpr,
}

Expr :: struct
{
	using node:   Node,
	derived_expr: AnyExpr,
}

AnyNode :: union
{
	^Scope,
	^Stmnt,
	^Expr,
	^EnumVariant,
}

Node :: struct
{
	span:    Span,
	type:    ^Type,
	derived: AnyNode,
}


new_node :: proc( $T: typeid, span: Span ) -> ^T
{
	new_node, _     := mem.new( T, tl_ast_allocator )
	new_node.span    = span
	base: ^Node      = new_node
	_                = base

	when intrinsics.type_has_field( T, "derived_stmnt" ) {
		new_node.derived       = cast(^Stmnt) new_node
		new_node.derived_stmnt = new_node
	}

	when intrinsics.type_has_field( T, "derived_expr" ) {
		new_node.derived      = cast(^Expr) new_node
		new_node.derived_expr = new_node
	}

	return new_node
}
