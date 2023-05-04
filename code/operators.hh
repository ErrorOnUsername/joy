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
		case BinaryOpKind::AndAssign:
		case BinaryOpKind::OrAssign:
		case BinaryOpKind::XorAssign:
			return true;
		default:
			return false;
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
	};
}
