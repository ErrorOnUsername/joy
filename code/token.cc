#include "token.hh"
#include <cassert>

char const* Token_GetKindAsString( TokenKind kind )
{
	switch ( kind )
	{
		case TK::Invalid:          return "invalid";
		case TK::EndOfFile:        return "EOF";
		case TK::EndOfLine:        return "EOL";
		case TK::LSquare:          return "[";
		case TK::RSquare:          return "]";
		case TK::LCurly:           return "{";
		case TK::RCurly:           return "}";
		case TK::LParen:           return "(";
		case TK::RParen:           return ")";
		case TK::Bang:             return "!";
		case TK::NEQ:              return "!=";
		case TK::Dollar:           return "$";
		case TK::Percent:          return "%";
		case TK::PercentAssign:    return "%=";
		case TK::Caret:            return "^";
		case TK::XOR:              return "^^";
		case TK::CaretAssign:      return "^=";
		case TK::Ampersand:        return "&";
		case TK::AND:              return "&&";
		case TK::AmpersandAssign:  return "&=";
		case TK::Star:             return "*";
		case TK::StarAssign:       return "*=";
		case TK::Minus:            return "-";
		case TK::MinusMinus:       return "--";
		case TK::MinusAssign:      return "-=";
		case TK::ThinArrow:        return "->";
		case TK::Plus:             return "+";
		case TK::PlusPlus:         return "++";
		case TK::PlusAssign:       return "+=";
		case TK::Assign:           return "=";
		case TK::EQ:               return "==";
		case TK::ThiccArrow:       return "=>";
		case TK::Pipe:             return "|";
		case TK::OR:               return "||";
		case TK::PipeAssign:       return "|=";
		case TK::Tilde:            return "~";
		case TK::TildeAssign:      return "~=";
		case TK::Semicolon:        return ";";
		case TK::Colon:            return ":";
		case TK::DoubleColon:      return "::";
		case TK::ColonAssign:      return ":=";
		case TK::Comma:            return ",";
		case TK::Dot:              return ".";
		case TK::DotDot:           return "..";
		case TK::LAngle:           return "<";
		case TK::LShift:           return "<<";
		case TK::LEQ:              return "<=";
		case TK::RAngle:           return ">";
		case TK::RShift:           return ">>";
		case TK::GEQ:              return ">=";
		case TK::Slash:            return "/";
		case TK::SlashAssign:      return "/=";
		case TK::Ident:            return "identifier";
		case TK::Number:           return "number";
		case TK::StringLiteral:    return "string literal";
		case TK::CharLiteral:      return "char literal";
		case TK::DirectiveLoad:    return "#load";
		case TK::KeywordTrue:      return "true";
		case TK::KeywordFalse:     return "false";
		case TK::KeywordDecl:      return "decl";
		case TK::KeywordLet:       return "let";
		case TK::KeywordIf:        return "if";
		case TK::KeywordElse:      return "else";
		case TK::KeywordFor:       return "for";
		case TK::KeywordWhile:     return "while";
		case TK::KeywordLoop:      return "loop";
		case TK::KeywordContinue:  return "continue";
		case TK::KeywordBreak:     return "break";
		case TK::KeywordReturn:    return "return";
		case TK::KeywordIn:        return "in";
		case TK::KeywordAs:        return "as";
		case TK::KeywordStruct:    return "struct";
		case TK::KeywordEnum:      return "enum";
		case TK::KeywordUnion:     return "union";
		case TK::PrimitiveNothing: return "nothing";
		case TK::PrimitiveBool:    return "bool";
		case TK::PrimitiveChar:    return "char";
		case TK::PrimitiveU8:      return "ubyte";
		case TK::PrimitiveI8:      return "ibyte";
		case TK::PrimitiveU16:     return "uword";
		case TK::PrimitiveI16:     return "iword";
		case TK::PrimitiveU32:     return "ulong";
		case TK::PrimitiveI32:     return "ilong";
		case TK::PrimitiveU64:     return "uquad";
		case TK::PrimitiveI64:     return "iquad";
		case TK::PrimitiveF32:     return "flong";
		case TK::PrimitiveF64:     return "fquad";
		case TK::PrimitiveRawPtr:  return "rawptr";
		case TK::PrimitiveString:  return "string";
		case TK::PrimitiveCString: return "cstring";
		default:                   return "UNKNOWN TOKEN";
	}

	return "UNKNOWN TOKEN";
}


Span join_span( Span const& left, Span const& right )
{
	assert( left.file_id == right.file_id );
	assert( left.line == right.line );

	return Span { left.file_id, left.start, right.end, left.line };
}
