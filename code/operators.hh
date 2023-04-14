#pragma once
#include <cstdint>


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
