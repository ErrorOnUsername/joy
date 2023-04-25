#include "parser.hh"

#include "log.hh"
#include "profiling.hh"


Parser::Parser()
	: lex_info()
	, seen_tokens()
	, node_arena( 16 * 1024 )
{
}


Module Parser::process_module( std::string const& path )
{
	TIME_PROC();

	Module module;
	{
		// Initialize the module with the global scope
		Scope root_scope { };
		module.scopes.append( root_scope );

		current_scope = &module.scopes[0];
	}


	lex_info = FileManager_GetOrCreateFileInfo( path.c_str() );
	// seed with first token
	seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	for ( ;; )
	{
		consume_newlines();

		Token& tk = curr_tk();

		switch ( tk.kind )
		{
			case TK::DirectiveLoad:
				log_span_fatal( tk.span, "Implement module loading!" );
				break;
			case TK::KeywordLet:
				parse_let_stmnt();
				break;
			case TK::KeywordDecl:
				parse_decl_stmnt();
				break;
			default:
				log_span_fatal( tk.span, "Expected 'decl', 'let', or a directive, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}
	}

	return module;
}


enum class DeclStmntKind : uint8_t {
	Invalid,
	Constant,
	Procedure,
	Struct,
	Enum,
	Union,
};


static DeclStmntKind decl_stmnt_kind_from_token_kind( TokenKind kind )
{
	switch ( kind )
	{
		case TK::LParen:        return DeclStmntKind::Procedure;
		case TK::KeywordStruct: return DeclStmntKind::Struct;
		case TK::KeywordEnum:   return DeclStmntKind::Enum;
		case TK::KeywordUnion:  return DeclStmntKind::Union;
		default:                return DeclStmntKind::Constant;
	}

	return DeclStmntKind::Invalid;
}


void Parser::parse_decl_stmnt()
{
	TIME_PROC();

	Token& name_tk = next_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected identifier after 'decl', but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected identifier after constant declaration's name, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	Token& determinant_tk = next_tk();
	DeclStmntKind decl_stmnt_kind = decl_stmnt_kind_from_token_kind( determinant_tk.kind );
	switch ( decl_stmnt_kind )
	{
		case DeclStmntKind::Constant:  parse_constant_decl();  break;
		case DeclStmntKind::Procedure: parse_procedure_decl(); break;
		case DeclStmntKind::Struct:    parse_struct_decl();    break;
		case DeclStmntKind::Enum:      parse_enum_decl();      break;
		case DeclStmntKind::Union:     parse_union_decl();     break;
		case DeclStmntKind::Invalid:
			log_span_fatal( determinant_tk.span, "Unexpected character in 'decl' stmnt" );
	}
}


void Parser::parse_let_stmnt()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement let parsing" );
}


void Parser::parse_constant_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement constant parsing" );
}


void Parser::parse_procedure_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement procedure parsing" );
}


void Parser::parse_struct_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement struct parsing" );
}


void Parser::parse_enum_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement enum parsing" );
}


void Parser::parse_union_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement union parsing" );
}


void Parser::consume_newlines()
{
	TIME_PROC();

	Token* curr = &curr_tk();

	while ( curr->kind == TK::EndOfLine )
	{
		curr = &next_tk();
	}
}


Token& Parser::peek_tk( int offset )
{
	TIME_PROC();

	size_t idx = (size_t)( std::max( (int)tk_idx + offset, 0 ) );

	if ( idx > tk_idx )
	{
		for ( size_t i = tk_idx; i < idx; i++ )
		{
			if ( i >= seen_tokens.size() )
				seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );
			else
				seen_tokens[i] = Lexer_GetNextToken( lex_info );
		}
	}

	return seen_tokens[idx];
}


Token& Parser::curr_tk()
{
	TIME_PROC();

	return peek_tk( 0 );
}


Token& Parser::next_tk()
{
	TIME_PROC();

	tk_idx++;

	if ( tk_idx >= seen_tokens.size() )
		seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	return seen_tokens[tk_idx];
}
