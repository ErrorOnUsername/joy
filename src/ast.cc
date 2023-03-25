#include "ast.hh"
#include <format>
#include <iostream>
#include <string>

#include "compiler.hh"

char const* bin_op_as_str( BinOpKind kind )
{
	switch ( kind )
	{
		case B_OP_INVAL: return "INVALID";

		case B_OP_MEMBER_ACCESS: return ".";
		case B_OP_RANGE:         return "..";

		case B_OP_ADD: return "+";
		case B_OP_SUB: return "-";
		case B_OP_MUL: return "*";
		case B_OP_DIV: return "/";
		case B_OP_MOD: return "%";

		case B_OP_L_AND: return "&&";
		case B_OP_B_AND: return "&";
		case B_OP_L_OR:  return "||";
		case B_OP_B_OR:  return "|";
		case B_OP_L_XOR: return "^^";
		case B_OP_B_XOR: return "^";

		case B_OP_EQ:  return "==";
		case B_OP_NEQ: return "!=";
		case B_OP_LT:  return "<";
		case B_OP_LEQ: return "<=";
		case B_OP_GT:  return ">";
		case B_OP_GEQ: return ">=";

		case B_OP_ADD_ASSIGN: return "+=";
		case B_OP_SUB_ASSIGN: return "-=";
		case B_OP_MUL_ASSIGN: return "*=";
		case B_OP_DIV_ASSIGN: return "/=";
		case B_OP_MOD_ASSIGN: return "%=";
		case B_OP_AND_ASSIGN: return "&=";
		case B_OP_OR_ASSIGN:  return "|=";
		case B_OP_XOR_ASSIGN: return "^=";
		case B_OP_ASSIGN:     return "=";
	}

	return "UNKNOWN OPERATOR (ast.cc)";
}

char const* u_op_as_str( UnaryOpKind kind )
{
	switch (kind) {
		case U_OP_NEG: return "-x";

		case U_OP_PRE_INC:  return "++x";
		case U_OP_PRE_DEC:  return "--x";
		case U_OP_POST_INC: return "x++";
		case U_OP_POST_DEC: return "x--";

		case U_OP_ADDR_OF: return "$x";
		case U_OP_DEREF:   return "*x";

		case U_OP_L_NOT: return "!x";

		case U_OP_CAST: return "x as";
	}

	return "UNKNOWN UNARY OP (ast.cc)";
}

template<typename ...Args>
static std::string format_string( std::string const& fmt, Args... args )
{
	int size = std::snprintf( nullptr, 0, fmt.c_str(), args... ) + 1;
	if ( size <= 0 )
		return std::string();

	char* buf = new char[(size_t)size];

	std::snprintf( buf, (size_t)size, fmt.c_str(), args... );
	std::string ret ( buf, buf + ( ( size_t )size - 1 ) );

	delete[] buf;

	return ret;
}

std::string dump_expr_internal( Expr* expr, size_t indent_level )
{
	std::string dump_raw;

	auto print_leading = [indent_level]( std::string& out )
	{
		for ( size_t i = 0; i < indent_level; i++ )
			out.append( "  " );
	};

	switch ( expr->kind )
	{
		case EXPR_BOOL:
		{
			ConstBoolExpr* as_bool = (ConstBoolExpr*)expr;

			print_leading( dump_raw );
			dump_raw.append( format_string( "BOOL: %c\n", as_bool->value ) );

			break;
		}
		case EXPR_NUMBER:
		{
			ConstNumberExpr* as_num = (ConstNumberExpr*)expr;

			print_leading( dump_raw );
			dump_raw.append( "NUMBER: " );

			switch ( as_num->num.kind )
			{
				case NK_FLOAT:
					dump_raw.append( format_string( "%f", as_num->num.floating_point ) );
					break;
				case NK_UINT:
					dump_raw.append( format_string( "%u", as_num->num.uint ) );
					break;
				case NK_INT:
					dump_raw.append( format_string( "%d", as_num->num.sint ) );
					break;
			}

			dump_raw.append( "\n" );

			break;
		}
		case EXPR_STRING:
		{
			ConstStringExpr* str = (ConstStringExpr*)expr;

			print_leading( dump_raw );
			dump_raw.append( format_string( "STR: \"%s\"\n", str->str.c_str() ) );

			break;
		}
		case EXPR_CHAR:
		{
			ConstCharExpr* ch = (ConstCharExpr*)expr;

			print_leading( dump_raw );
			dump_raw.append( format_string( "CHAR: '%c'\n", (char)ch->codepoint ) );

			break;
		}
		case EXPR_VAR:
		{
			VarExpr* var = (VarExpr*)expr;

			print_leading( dump_raw );
			dump_raw.append( format_string( "VAR: %s\n", var->name.c_str() ) );

			break;
		}
		case EXPR_RANGE:
		{
			print_leading( dump_raw );
			dump_raw.append( "RANGE:\n" );

			break;
		}
		case EXPR_PROC_CALL:
		{
			print_leading( dump_raw );
			dump_raw.append( "PROC_CALL:\n" );

			break;
		}
		case EXPR_BIN_OP:
		{
			BinOpExpr* bop = (BinOpExpr*)expr;
			print_leading( dump_raw );

			dump_raw.append( format_string( "BIN_OP: %s\n", bin_op_as_str( bop->op_kind ) ) );
			dump_raw.append( dump_expr_internal( bop->lhs, indent_level + 1 ) );
			dump_raw.append( dump_expr_internal( bop->rhs, indent_level + 1 ) );

			break;
		}
		case EXPR_UNARY_OP:
		{
			UnaryOpExpr* uop = (UnaryOpExpr*)expr;
			print_leading( dump_raw );

			dump_raw.append( format_string( "UNARY_OP: %s\n", u_op_as_str( uop->op_kind ) ) );
			dump_raw.append( dump_expr_internal( uop->operand, indent_level + 1 ) );

			break;
		}
	}

	return dump_raw;
}

void dump_expr( Expr* expr )
{
	std::string dump_raw = dump_expr_internal( expr, 0 );
	Compiler::log( "%s", dump_raw.c_str() );
}

bool is_assign_op( BinOpKind kind )
{
	switch ( kind )
	{
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

		case B_OP_INVAL:
			return false;
	}

	Compiler::warn( "Unknown binary operator: %s", kind );
	return false;
}

int64_t op_priority( BinOpKind kind )
{
	switch ( kind )
	{
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

		case B_OP_INVAL:
			return -1;
	}

	Compiler::warn( "Unknown binary operator: %s", kind );
	return -1;
}
