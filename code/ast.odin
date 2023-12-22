package main

import "core:intrinsics"
import "core:mem"


Package :: struct
{
	name: string,
	imports: [dynamic]^Package,
	modules: [dynamic]^Module,
}

Module :: struct
{
	file_id:    FileID,
	owning_pkg: ^Package,
	file_scope: ^Scope,
}


SymbolTable :: map[string]^Stmnt

Scope :: struct
{
	using node: Node,
	symbols:    SymbolTable,
	stmnts:     [dynamic]^Stmnt,
	parent:     ^Scope,
}


AddressingMode :: enum
{
	Invalid,
	Type,
	Constant,
	Variable,
	Value,
}



//
// Declarations
//

StructDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
	memb_lookup: SymbolTable,
	members:     [dynamic]^VarDecl,
}

EnumVariant :: struct
{
	using stmnt: Stmnt,
	owning_enum: ^EnumDecl,
	name:        string,
}

EnumDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
	underlying:  ^Type,
	type_hint:   ^Expr,
	vari_lookup: SymbolTable,
	variants:    [dynamic]^EnumVariant,
}

UnionDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
}

ProcDecl :: struct
{
	using stmnt: Stmnt,
	owning_mod:  ^Module,
	name:        string,
	params:      [dynamic]^VarDecl,
	body:        ^Scope,
}

VarDecl :: struct
{
	using stmnt:   Stmnt,
	name:          string,
	type_hint:     ^Expr,
	default_value: ^Expr,
}


//
// Statements
//

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
	cond:        ^Expr,
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
	ref:        ^Stmnt,
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
	lhs:                   ^Expr,
	right_bound_inclusive: bool,
	rhs:                   ^Expr,
}

FieldAccessExpr :: struct
{
	using expr: Expr,
	owner:      ^Expr,
	field:      ^Expr,
}


BinaryOperator :: enum
{
	Invalid,

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

		case .Multiply, .Divide, .Modulo:
			return 12

		case .Add, .Subtract:
			return 11

		case .BitwiseLShift, .BitwiseRShift:
			return 10

		case .LessThanOrEq, .LessThan,
		     .GreaterThanOrEq, .GreaterThan:
			return 9

		case .Equal, .NotEqual:
			return 8

		case .BitwiseAnd: return 7
		case .BitwiseOr:  return 6
		case .BitwiseXOr: return 5
		case .LogicalAnd: return 4
		case .LogicalOr:  return 3
		case .LogicalXOr: return 2

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


PointerTypeExpr :: struct
{
	using expr: Expr,
	is_mut:     bool,
	base_type:  ^Expr,
}


SliceTypeExpr :: struct
{
	using expr: Expr,
	base_type:  ^Expr,
}


ArrayTypeExpr :: struct
{
	using expr: Expr,
	base_type:  ^Expr,
	size_expr:  ^Expr,
}


AnyStmnt :: union
{
	^StructDecl,
	^EnumDecl,
	^EnumVariant,
	^UnionDecl,
	^ProcDecl,
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
	^FieldAccessExpr,
	^PointerTypeExpr,
	^SliceTypeExpr,
	^ArrayTypeExpr,
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
}

Node :: struct
{
	span:        Span,
	type:        ^Type,
	derived:     AnyNode,
	check_state: CheckState,
}

CheckState :: enum
{
	Unresolved,
	Resolved,
}


new_node :: proc( $T: typeid, span: Span ) -> ^T
{
	new_node, _          := mem.new( T, tl_ast_allocator )
	new_node.span         = span
	new_node.check_state  = .Unresolved
	base: ^Node           = new_node
	_                     = base

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
