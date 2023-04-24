#include "parser.hh"

#include "log.hh"


Parser::Parser()
	: lex_info()
	, seen_tokens()
	, node_arena( 16 * 1024 )
{
}


Module Parser::process_module( std::string const& path )
{
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


void Parser::parse_decl_stmnt()
{
	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement decl parsing" );
}


void Parser::parse_let_stmnt()
{
	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement let parsing" );
}


void Parser::consume_newlines()
{
	Token* curr = &curr_tk();

	while ( curr->kind == TK::EndOfLine )
	{
		curr = &next_tk();
	}
}


Token& Parser::peek_tk( int offset )
{
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
	return peek_tk( 0 );
}


Token& Parser::next_tk()
{
	tk_idx++;

	if ( tk_idx > seen_tokens.size() )
		seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	return seen_tokens[tk_idx];
}
