#include "ast.hh"


char const* AstNodeKind_AsStr( NodeKind kind )
{
	switch( kind )
	{
		case AstNodeKind::Invalid:              return "Invalid";
		case AstNodeKind::IntegerLiteral:       return "IntegerLiteral";
		case AstNodeKind::FloatingPointLiteral: return "FloatingPointLiteral";
		case AstNodeKind::StringLiteral:        return "StringLiteral";
		case AstNodeKind::CharacterLiteral:     return "CharacterLiteral";
		case AstNodeKind::BinaryOperation:      return "BinaryOperation";
		case AstNodeKind::Range:                return "Range";
		case AstNodeKind::UnaryOperation:       return "UnaryOperation";
		case AstNodeKind::VarDecl:              return "VarDecl";
		case AstNodeKind::StructDecl:           return "StructDecl";
		case AstNodeKind::EnumDecl:             return "EnumDecl";
		case AstNodeKind::UnionDecl:            return "UnionDecl";
		case AstNodeKind::UnionVariantMember:   return "UnionVariantMember";
		case AstNodeKind::ProcDecl:             return "ProcDecl";
		case AstNodeKind::IfStmnt:              return "IfStmnt";
		case AstNodeKind::VarRef:               return "VarRef";
		case AstNodeKind::ProcCall:             return "ProcCall";
		case AstNodeKind::LexicalBlock:         return "LexicalBlock";
		case AstNodeKind::ForLoop:              return "ForLoop";
		case AstNodeKind::WhileLoop:            return "WhileLoop";
		case AstNodeKind::InfiniteLoop:         return "InfiniteLoop";
		case AstNodeKind::ContinueStmnt:        return "ContinueStmnt";
		case AstNodeKind::BreakStmnt:           return "BreakStmnt";
		case AstNodeKind::ReturnStmnt:          return "ReturnStmnt";
		case AstNodeKind::LoadStmnt:            return "LoadStmnt";
		default:                                return "UNKNOWN NODE KIND";
	}
}
