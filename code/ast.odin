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
	using expr: Expr,
	variant:    ScopeVariant,
	symbols:    SymbolTable,
	stmnts:     [dynamic]^Stmnt,
	parent:     ^Scope,
}

ScopeVariant :: enum
{
	Struct,
	Enum,
	Union,
	Logic,
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
// Statements
//

ConstDecl :: struct
{
	using stmnt:   Stmnt,
	name:          string,
	type_hint:     ^Expr,
	value:         ^Expr,
}

VarDecl :: struct
{
	using stmnt:   Stmnt,
	name:          string,
	type_hint:     ^Expr,
	default_value: ^Expr,
}

EnumVariantDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
}

UnionVariantDecl :: struct
{
	using stmnt: Stmnt,
	name:        string,
	sc:          ^Scope,
}

ExprStmnt :: struct
{
	using stmnt: Stmnt,
	expr:        ^Expr,
}

ContinueStmnt :: struct
{
	using stmnt: Stmnt,
}

BreakStmnt :: struct
{
	using stmnt: Stmnt,
}

ReturnStmnt :: struct
{
	using stmnt: Stmnt,
	expr:        ^Expr,
}


//
// Expressions
//

ProcProto :: struct
{
	using expr: Expr,
	name:       string,
	params:     [dynamic]^VarDecl,
	body:       ^Scope,
}

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

StructLiteralExpr :: struct
{
	using expr: Expr,
}

IfExpr :: struct
{
	using expr: Expr,
	cond:       ^Expr,
	then:       ^Scope,
	else_block: ^IfExpr,
}

ForLoop :: struct
{
	using expr: Expr,
	iter_ident: ^Ident,
	range:      ^Expr,
	body:       ^Scope,
}

WhileLoop :: struct
{
	using expr: Expr,
	cond:       ^Expr,
	body:       ^Scope,
}

InfiniteLoop :: struct
{
	using expr: Expr,
	body:       ^Scope,
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

UnaryOpExpr :: struct
{
	using expr: Expr,
	op:         Token,
	rand:       ^Expr,
}

BinOpExpr :: struct
{
	using expr: Expr,
	op:         Token,
	lhs:        ^Expr,
	rhs:        ^Expr,
}

bin_op_priority :: proc( op: ^Token ) -> int
{
	#partial switch op.kind {
		case .Invalid: return -1

		case .Dot: return 13

		case .Star, .Slash, .Percent:
			return 12

		case .Plus, .Minus:
			return 11

		case .LShift, .RShift:
			return 10

		case .LessThanOrEqual, .LAngle,
		     .GreaterThanOrEqual, .RAngle:
			return 9

		case .Equal, .NotEqual:
			return 8

		case .Ampersand:       return 7
		case .Pipe:            return 6
		case .Caret:           return 5
		case .DoubleAmpersand: return 4
		case .DoublePipe:      return 3
		case .DoubleCaret:     return 2

		case .Assign, .PlusAssign,
			 .MinusAssign, .StarAssign,
			 .SlashAssign, .PercentAssign,
			 .AmpersandAssign, .PipeAssign, .CaretAssign:
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


PrimitiveTypeExpr :: struct
{
	using expr: Expr,
	prim: PrimitiveKind,
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
	^ConstDecl,
	^VarDecl,
	^EnumVariantDecl,
	^UnionVariantDecl,
	^ExprStmnt,
	^ContinueStmnt,
	^BreakStmnt,
	^ReturnStmnt,
}

Stmnt :: struct
{
	using node:    Node,
	derived_stmnt: AnyStmnt,
}

AnyExpr :: union
{
	^ProcProto,
	^Ident,
	^StringLiteralExpr,
	^NumberLiteralExpr,
	^StructLiteralExpr,
	^Scope,
	^IfExpr,
	^ForLoop,
	^WhileLoop,
	^InfiniteLoop,
	^RangeExpr,
	^UnaryOpExpr,
	^BinOpExpr,
	^ProcCallExpr,
	^FieldAccessExpr,
	^PrimitiveTypeExpr,
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
