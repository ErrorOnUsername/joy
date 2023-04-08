#include "token.hh"
#include "ast.hh"

char const* tk_as_str( TokenKind kind )
{
	switch ( kind )
	{
		case TK_INVAL:
			return "TK_INVAL";

		case TK_EOF:
			return "TK_EOF";
		case TK_EOL:
			return "TK_EOL";

		case TK_L_SQUARE:
			return "TK_L_SQUARE";
		case TK_R_SQUARE:
			return "TK_R_SQUARE";
		case TK_L_CURLY:
			return "TK_L_CURLY";
		case TK_R_CURLY:
			return "TK_R_CURLY";
		case TK_L_PAREN:
			return "TK_L_PAREN";
		case TK_R_PAREN:
			return "TK_R_PAREN";

		case TK_BANG:
			return "TK_BANG";
		case TK_NEQ:
			return "TK_NEQ";

		case TK_DOLLAR:
			return "TK_DOLLAR";

		case TK_PERCENT:
			return "TK_PERCENT";
		case TK_PERCENT_ASSIGN:
			return "TK_PERCENT_ASSIGN";

		case TK_CARET:
			return "TK_CARET";
		case TK_XOR:
			return "TK_XOR";
		case TK_CARET_ASSIGN:
			return "TK_CARET_ASSIGN";

		case TK_AMPERSAND:
			return "TK_AMPERSAND";
		case TK_AND:
			return "TK_AND";
		case TK_AMPERSAND_ASSIGN:
			return "TK_AMPERSAND_ASSIGN";

		case TK_STAR:
			return "TK_STAR";
		case TK_STAR_ASSIGN:
			return "TK_STAR_ASSIGN";

		case TK_MINUS:
			return "TK_MINUS";
		case TK_MINUS_MINUS:
			return "TK_MINUS_MINUS";
		case TK_MINUS_ASSIGN:
			return "TK_MINUS_ASSIGN";
		case TK_THIN_ARROW:
			return "TK_THIN_ARROW";

		case TK_PLUS:
			return "TK_PLUS";
		case TK_PLUS_PLUS:
			return "TK_PLUS_PLUS";
		case TK_PLUS_ASSIGN:
			return "TK_PLUS_ASSIGN";

		case TK_ASSIGN:
			return "TK_ASSIGN";
		case TK_EQ:
			return "TK_EQ";
		case TK_THICC_ARROW:
			return "TK_THICC_ARROW";

		case TK_PIPE:
			return "TK_PIPE";
		case TK_OR:
			return "TK_OR";
		case TK_PIPE_ASSIGN:
			return "TK_PIPE_ASSIGN";

		case TK_SEMICOLON:
			return "TK_SEMICOLON";

		case TK_COLON:
			return "TK_COLON";
		case TK_DOUBLE_COLON:
			return "TK_DOUBLE_COLON";
		case TK_COLON_ASSIGN:
			return "TK_COLON_ASSIGN";

		case TK_COMMA:
			return "TK_COMMA";

		case TK_DOT:
			return "TK_DOT";
		case TK_DOT_DOT:
			return "TK_DOT_DOT";

		case TK_L_ANGLE:
			return "TK_L_ANGLE";
		case TK_LEQ:
			return "TK_LEQ";

		case TK_R_ANGLE:
			return "TK_R_ANGLE";
		case TK_GEQ:
			return "TK_GEQ";

		case TK_SLASH:
			return "TK_SLASH";
		case TK_SLASH_ASSIGN:
			return "TK_SLASH_ASSIGN";

		case TK_IDENT:
			return "TK_IDENT";
		case TK_NUMBER:
			return "TK_NUMBER";
		case TK_STR_LIT:
			return "TK_STR_LIT";
		case TK_CHAR_LIT:
			return "TK_CHAR_LIT";
		case TK_BOOL_T:
			return "TK_BOOL_T";
		case TK_BOOL_F:
			return "TK_BOOL_F";

		case TK_CD_LOAD:
			return "TK_CD_LOAD";

		case TK_KW_DECL:
			return "TK_KW_DECL";
		case TK_KW_LET:
			return "TK_KW_LET";
		case TK_KW_IF:
			return "TK_KW_IF";
		case TK_KW_ELSE:
			return "TK_KW_ELSE";
		case TK_KW_FOR:
			return "TK_KW_FOR";
		case TK_KW_WHILE:
			return "TK_KW_WHILE";
		case TK_KW_LOOP:
			return "TK_KW_LOOP";
		case TK_KW_CONTINUE:
			return "TK_KW_CONTINUE";
		case TK_KW_BREAK:
			return "TK_KW_BREAK";
		case TK_KW_RETURN:
			return "TK_KW_RETURN";
		case TK_KW_IN:
			return "TK_KW_IN";
		case TK_KW_AS:
			return "TK_KW_AS";
		case TK_KW_STRUCT:
			return "TK_KW_STRUCT";
		case TK_KW_ENUM:
			return "TK_KW_ENUM";
		case TK_KW_UNION:
			return "TK_KW_UNION";

		case TK_TY_NOTHING:
			return "TK_TY_NOTHING";
		case TK_TY_CHAR:
			return "TK_TY_CHAR";
		case TK_TY_BOOL:
			return "TK_TY_BOOL";
		case TK_TY_U8:
			return "TK_TY_U8";
		case TK_TY_I8:
			return "TK_TY_I8";
		case TK_TY_U16:
			return "TK_TY_U16";
		case TK_TY_I16:
			return "TK_TY_I16";
		case TK_TY_U32:
			return "TK_TY_U32";
		case TK_TY_I32:
			return "TK_TY_I32";
		case TK_TY_U64:
			return "TK_TY_U64";
		case TK_TY_I64:
			return "TK_TY_I64";
		case TK_TY_F32:
			return "TK_TY_F32";
		case TK_TY_F64:
			return "TK_TY_F64";
		case TK_TY_RAWPTR:
			return "TK_TY_RAWPTR";
		case TK_TY_STR:
			return "TK_TY_STR";
		case TK_TY_CSTR:
			return "TK_TY_CSTR";

		default:
			return "UNKNOWN (ADD TO token.h)";
	}
}

BinOpKind tk_as_operator( TokenKind kind )
{
	switch ( kind )
	{
		case TK_NEQ:
			return B_OP_NEQ;
		case TK_PERCENT_ASSIGN:
			return B_OP_MOD_ASSIGN;
		case TK_CARET:
			return B_OP_B_XOR;
		case TK_XOR:
			return B_OP_L_XOR;
		case TK_CARET_ASSIGN:
			return B_OP_XOR_ASSIGN;
		case TK_AMPERSAND:
			return B_OP_B_AND;
		case TK_AND:
			return B_OP_L_AND;
		case TK_AMPERSAND_ASSIGN:
			return B_OP_AND_ASSIGN;
		case TK_STAR:
			return B_OP_MUL;
		case TK_STAR_ASSIGN:
			return B_OP_MUL_ASSIGN;
		case TK_MINUS:
			return B_OP_SUB;
		case TK_MINUS_ASSIGN:
			return B_OP_SUB_ASSIGN;
		case TK_PLUS:
			return B_OP_ADD;
		case TK_PLUS_ASSIGN:
			return B_OP_ADD_ASSIGN;
		case TK_ASSIGN:
			return B_OP_ASSIGN;
		case TK_EQ:
			return B_OP_EQ;
		case TK_PIPE:
			return B_OP_B_OR;
		case TK_OR:
			return B_OP_L_OR;
		case TK_PIPE_ASSIGN:
			return B_OP_OR_ASSIGN;
		case TK_L_ANGLE:
			return B_OP_LT;
		case TK_LEQ:
			return B_OP_LEQ;
		case TK_R_ANGLE:
			return B_OP_GT;
		case TK_GEQ:
			return B_OP_GEQ;
		case TK_SLASH:
			return B_OP_DIV;
		case TK_SLASH_ASSIGN:
			return B_OP_DIV_ASSIGN;
		case TK_DOT_DOT:
			return B_OP_RANGE;
	}

	return B_OP_INVAL;
}

bool is_tk_operator( TokenKind kind )
{
	switch ( kind )
	{
		case TK_NEQ:
		case TK_PERCENT_ASSIGN:
		case TK_CARET:
		case TK_XOR:
		case TK_CARET_ASSIGN:
		case TK_AMPERSAND:
		case TK_AND:
		case TK_AMPERSAND_ASSIGN:
		case TK_STAR:
		case TK_STAR_ASSIGN:
		case TK_MINUS:
		case TK_MINUS_ASSIGN:
		case TK_PLUS:
		case TK_PLUS_ASSIGN:
		case TK_ASSIGN:
		case TK_EQ:
		case TK_PIPE:
		case TK_OR:
		case TK_PIPE_ASSIGN:
		case TK_L_ANGLE:
		case TK_LEQ:
		case TK_R_ANGLE:
		case TK_GEQ:
		case TK_SLASH:
		case TK_SLASH_ASSIGN:
		case TK_DOT:
		case TK_DOT_DOT:
			return true;
	}

	return false;
}
