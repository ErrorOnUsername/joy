#include "ast.h"
#include <iostream>

char const* bin_op_as_str(BinOpKind kind)
{
	switch (kind) {
		case B_OP_INVAL: return "INVALID";

		case B_OP_MEMBER_ACCESS: return ".";
		case B_OP_RANGE: return "..";

		case B_OP_ADD: return "+";
		case B_OP_SUB: return "-";
		case B_OP_MUL: return "*";
		case B_OP_DIV: return "/";
		case B_OP_MOD: return "%";

		case B_OP_L_AND: return "&&";
		case B_OP_B_AND: return "&";
		case B_OP_L_OR: return "||";
		case B_OP_B_OR: return "|";
		case B_OP_L_XOR: return "^^";
		case B_OP_B_XOR: return "^";

		case B_OP_EQ: return "==";
		case B_OP_NEQ: return "!=";
		case B_OP_LT: return "<";
		case B_OP_LEQ: return "<=";
		case B_OP_GT: return ">";
		case B_OP_GEQ: return ">=";

		case B_OP_ADD_ASSIGN: return "+=";
		case B_OP_SUB_ASSIGN: return "-=";
		case B_OP_MUL_ASSIGN: return "*=";
		case B_OP_DIV_ASSIGN: return "/=";
		case B_OP_MOD_ASSIGN: return "%=";
		case B_OP_AND_ASSIGN: return "&=";
		case B_OP_OR_ASSIGN: return "|=";
		case B_OP_XOR_ASSIGN: return "^=";
		case B_OP_ASSIGN: return "=";
	}
}

char const* u_op_as_str(UnaryOpKind kind)
{
	switch (kind) {
		case U_OP_NEG: return "-x";

		case U_OP_PRE_INC: return "++x";
		case U_OP_PRE_DEC: return "--x";
		case U_OP_POST_INC: return "x++";
		case U_OP_POST_DEC: return "x--";

		case U_OP_ADDR_OF: return "$x";
		case U_OP_DEREF: return "*x";

		case U_OP_L_NOT: return "!x";

		case U_OP_CAST: return "x as";
	}
}

void dump_expr(Expr* expr, size_t indent_level)
{
	auto print_leading = [indent_level]() {
		for (size_t i = 0; i < indent_level; i++)
			std::cout << "  ";
	};

	switch (expr->kind) {
		case EXPR_BOOL: {
			ConstBoolExpr* as_bool = (ConstBoolExpr*)expr;

			print_leading();
			std::cout << "BOOL: " << as_bool->value << std::endl;

			break;
		}
		case EXPR_NUMBER: {
			ConstNumberExpr* as_num = (ConstNumberExpr*)expr;

			print_leading();
			std::cout << "NUMBER: ";

			switch (as_num->num.kind) {
				case NK_FLOAT:
					std::cout << as_num->num.floating_point;
					break;
				case NK_UINT:
					std::cout << as_num->num.uint;
					break;
				case NK_INT:
					std::cout << as_num->num.sint;
					break;
			}

			std::cout << std::endl;

			break;
		}
		case EXPR_STRING: {
			ConstStringExpr* str = (ConstStringExpr*)expr;

			print_leading();
			std::cout << "STR: \"" << str->str << "\"" << std::endl;

			break;
		}
		case EXPR_CHAR: {
			ConstCharExpr* ch = (ConstCharExpr*)expr;

			print_leading();
			std::cout << "CHAR: '" << (char)ch->codepoint << "'" << std::endl;

			break;
		}
		case EXPR_VAR: {
			VarExpr* var = (VarExpr*)expr;

			print_leading();
			std::cout << "VAR: " << var->name << std::endl;

			break;
		}
		case EXPR_RANGE: {
			print_leading();
			std::cout << "RANGE:" << std::endl;

			break;
		}
		case EXPR_PROC_CALL: {
			print_leading();

			std::cout << "PROC_CALL:" << std::endl;

			break;
		}
		case EXPR_BIN_OP: {
			BinOpExpr* bop = (BinOpExpr*)expr;
			print_leading();

			std::cout << "BIN_OP: " << bin_op_as_str(bop->op_kind) << std::endl;
			dump_expr(bop->lhs, indent_level + 1);
			dump_expr(bop->rhs, indent_level + 1);

			break;
		}
		case EXPR_UNARY_OP: {
			UnaryOpExpr* uop = (UnaryOpExpr*)expr;
			print_leading();

			std::cout << "UNARY_OP: " << u_op_as_str(uop->op_kind) << std::endl;
			dump_expr(uop->operand, indent_level + 1);

			break;
		}
	}
}

bool is_assign_op(BinOpKind kind)
{
	switch (kind) {
		case B_OP_MEMBER_ACCESS:
		case B_OP_RANGE:
		case B_OP_MUL:
		case B_OP_DIV:
		case B_OP_MOD:
		case B_OP_ADD:
		case B_OP_SUB:
		case B_OP_LT:
		case B_OP_LEQ:
		case B_OP_GT:
		case B_OP_GEQ:
		case B_OP_EQ:
		case B_OP_NEQ:
		case B_OP_B_AND:
		case B_OP_B_OR:
		case B_OP_B_XOR:
		case B_OP_L_AND:
		case B_OP_L_OR:
		case B_OP_L_XOR:
			return false;

		case B_OP_ASSIGN:
		case B_OP_ADD_ASSIGN:
		case B_OP_SUB_ASSIGN:
		case B_OP_MUL_ASSIGN:
		case B_OP_DIV_ASSIGN:
		case B_OP_MOD_ASSIGN:
		case B_OP_AND_ASSIGN:
		case B_OP_OR_ASSIGN:
		case B_OP_XOR_ASSIGN:
			return true;
	}
}

int64_t op_priority(BinOpKind kind)
{
	switch (kind) {
		case B_OP_MEMBER_ACCESS:
			return 14;

		case B_OP_RANGE:
			return 13;

		case B_OP_MUL:
		case B_OP_DIV:
		case B_OP_MOD:
			return 12;

		case B_OP_ADD:
		case B_OP_SUB:
			return 11;

		case B_OP_LT:
		case B_OP_LEQ:
		case B_OP_GT:
		case B_OP_GEQ:
			return 9;

		case B_OP_EQ:
		case B_OP_NEQ:
			return 8;

		case B_OP_B_AND: return 7;
		case B_OP_B_OR:  return 6;
		case B_OP_B_XOR: return 5;

		case B_OP_L_AND: return 4;
		case B_OP_L_OR:  return 3;
		case B_OP_L_XOR: return 2;

		case B_OP_ASSIGN:
		case B_OP_ADD_ASSIGN:
		case B_OP_SUB_ASSIGN:
		case B_OP_MUL_ASSIGN:
		case B_OP_DIV_ASSIGN:
		case B_OP_MOD_ASSIGN:
		case B_OP_AND_ASSIGN:
		case B_OP_OR_ASSIGN:
		case B_OP_XOR_ASSIGN:
			return 1;
	}
}
