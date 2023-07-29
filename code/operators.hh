#pragma once
#include <cstdint>

#include "token.hh"

using BinOpKind = uint16_t;
namespace BinaryOpKind
{
	enum {
		Invalid,

		MemberAccess,
		Range,

		Multiply,
		Divide,
		Modulo,

		Add,
		Subtract,

		LessThan,
		LessThanOrEq,
		GreaterThan,
		GreaterThanOrEq,

		EqualTo,
		NotEqualTo,

		BitwiseAnd,
		BitwiseOr,
		BitwiseXor,

		LogicalAnd,
		LogicalOr,
		LogicalXor,

		Assign,
		AddAssign,
		SubtractAssign,
		MultiplyAssign,
		DivideAssign,
		ModuloAssign,
		NotAssign,
		AndAssign,
		OrAssign,
		XorAssign,
	};
}


inline static BinOpKind BinaryOperator_FromTK( Token& tk )
{
	switch ( tk.kind )
	{
		case TK::Dot:
			return BinaryOpKind::MemberAccess;
		case TK::DotDot:
			return BinaryOpKind::Range;
		case TK::Star:
			return BinaryOpKind::Multiply;
		case TK::Slash:
			return BinaryOpKind::Divide;
		case TK::Percent:
			return BinaryOpKind::Modulo;
		case TK::Plus:
			return BinaryOpKind::Add;
		case TK::Minus:
			return BinaryOpKind::Subtract;
		case TK::LAngle:
			return BinaryOpKind::LessThan;
		case TK::LEQ:
			return BinaryOpKind::LessThanOrEq;
		case TK::RAngle:
			return BinaryOpKind::GreaterThan;
		case TK::GEQ:
			return BinaryOpKind::GreaterThanOrEq;
		case TK::EQ:
			return BinaryOpKind::EqualTo;
		case TK::NEQ:
			return BinaryOpKind::NotEqualTo;
		case TK::Ampersand:
			return BinaryOpKind::BitwiseAnd;
		case TK::Pipe:
			return BinaryOpKind::BitwiseOr;
		case TK::Caret:
			return BinaryOpKind::BitwiseXor;
		case TK::AND:
			return BinaryOpKind::LogicalAnd;
		case TK::OR:
			return BinaryOpKind::LogicalOr;
		case TK::XOR:
			return BinaryOpKind::LogicalXor;
		case TK::Assign:
			return BinaryOpKind::Assign;
		case TK::PlusAssign:
			return BinaryOpKind::AddAssign;
		case TK::MinusAssign:
			return BinaryOpKind::SubtractAssign;
		case TK::StarAssign:
			return BinaryOpKind::MultiplyAssign;
		case TK::SlashAssign:
			return BinaryOpKind::DivideAssign;
		case TK::PercentAssign:
			return BinaryOpKind::ModuloAssign;
		case TK::TildeAssign:
			return BinaryOpKind::NotAssign;
		case TK::AmpersandAssign:
			return BinaryOpKind::AndAssign;
		case TK::PipeAssign:
			return BinaryOpKind::OrAssign;
		case TK::CaretAssign:
			return BinaryOpKind::XorAssign;
		default:
			return BinaryOpKind::Invalid;
	}
}


inline static int BinaryOperator_GetPriority( BinOpKind kind )
{
	switch ( kind )
	{
		case BinaryOpKind::Invalid: return -1;

		case BinaryOpKind::MemberAccess:
			return 13;

		case BinaryOpKind::Range:
			return 12;

		case BinaryOpKind::Multiply:
		case BinaryOpKind::Divide:
		case BinaryOpKind::Modulo:
			return 11;

		case BinaryOpKind::Add:
		case BinaryOpKind::Subtract:
			return 10;

		case BinaryOpKind::LessThan:
		case BinaryOpKind::LessThanOrEq:
		case BinaryOpKind::GreaterThan:
		case BinaryOpKind::GreaterThanOrEq:
			return 9;

		case BinaryOpKind::EqualTo:
		case BinaryOpKind::NotEqualTo:
			return 8;

		case BinaryOpKind::BitwiseAnd:
			return 7;
		case BinaryOpKind::BitwiseOr:
			return 6;
		case BinaryOpKind::BitwiseXor:
			return 5;
		case BinaryOpKind::LogicalAnd:
			return 4;
		case BinaryOpKind::LogicalOr:
			return 3;
		case BinaryOpKind::LogicalXor:
			return 2;

		case BinaryOpKind::Assign:
		case BinaryOpKind::AddAssign:
		case BinaryOpKind::SubtractAssign:
		case BinaryOpKind::MultiplyAssign:
		case BinaryOpKind::DivideAssign:
		case BinaryOpKind::ModuloAssign:
		case BinaryOpKind::NotAssign:
		case BinaryOpKind::AndAssign:
		case BinaryOpKind::OrAssign:
		case BinaryOpKind::XorAssign:
			return 1;
	}

	return -1;
}


inline static bool BinaryOperator_IsAssign( BinOpKind op )
{
	switch ( op )
	{
		case BinaryOpKind::Assign:
		case BinaryOpKind::AddAssign:
		case BinaryOpKind::SubtractAssign:
		case BinaryOpKind::MultiplyAssign:
		case BinaryOpKind::DivideAssign:
		case BinaryOpKind::ModuloAssign:
		case BinaryOpKind::NotAssign:
		case BinaryOpKind::AndAssign:
		case BinaryOpKind::OrAssign:
		case BinaryOpKind::XorAssign:
			return true;
		default:
			return false;
	}
}


inline static char const* BinaryOperator_AsStr( BinOpKind kind )
{
	switch ( kind )
	{
		case BinaryOpKind::Invalid:         return "INVALID";
		case BinaryOpKind::MemberAccess:    return ".";
		case BinaryOpKind::Range:           return "..";
		case BinaryOpKind::Multiply:        return "*";
		case BinaryOpKind::Divide:          return "/";
		case BinaryOpKind::Modulo:          return "%";
		case BinaryOpKind::Add:             return "+";
		case BinaryOpKind::Subtract:        return "-";
		case BinaryOpKind::LessThan:        return "<";
		case BinaryOpKind::LessThanOrEq:    return "<=";
		case BinaryOpKind::GreaterThan:     return ">";
		case BinaryOpKind::GreaterThanOrEq: return ">=";
		case BinaryOpKind::EqualTo:         return "==";
		case BinaryOpKind::NotEqualTo:      return "!=";
		case BinaryOpKind::BitwiseAnd:      return "&";
		case BinaryOpKind::BitwiseOr:       return "|";
		case BinaryOpKind::BitwiseXor:      return "^";
		case BinaryOpKind::LogicalAnd:      return "&&";
		case BinaryOpKind::LogicalOr:       return "||";
		case BinaryOpKind::LogicalXor:      return "^^";
		case BinaryOpKind::Assign:          return "=";
		case BinaryOpKind::AddAssign:       return "+=";
		case BinaryOpKind::SubtractAssign:  return "-=";
		case BinaryOpKind::MultiplyAssign:  return "*=";
		case BinaryOpKind::DivideAssign:    return "/=";
		case BinaryOpKind::ModuloAssign:    return "%=";
		case BinaryOpKind::NotAssign:       return "~=";
		case BinaryOpKind::AndAssign:       return "&=";
		case BinaryOpKind::OrAssign:        return "|=";
		case BinaryOpKind::XorAssign:       return "^=";
		default:                            return "UNKNOWN";
	}
}


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
		PrefixIncrement,
		PrefixDecrement,
		PostfixIncrement,
		PostfixDecrement,
	};
}


inline static char const* UnaryOperator_AsStr( UnOpKind kind )
{
	switch ( kind )
	{
		case UnaryOpKind::Invalid:          return "INVALID";
		case UnaryOpKind::LogicalNot:       return "!";
		case UnaryOpKind::BitwiseNot:       return "~";
		case UnaryOpKind::Negate:           return "-";
		case UnaryOpKind::Dereference:      return "*";
		case UnaryOpKind::AddressOf:        return "&";
		case UnaryOpKind::PrefixIncrement:  return "++x";
		case UnaryOpKind::PrefixDecrement:  return "--x";
		case UnaryOpKind::PostfixIncrement: return "x++";
		case UnaryOpKind::PostfixDecrement: return "x--";
		default:                            return "UNKNOWN";
	}
}
