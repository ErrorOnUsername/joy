#include "parser.hh"

#include "log.hh"


bool Parser::process_module( std::string const& path )
{
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
			case TK::KeywordDecl:
				log_span_fatal( tk.span, "Implement decl parsing!" );
				break;
			default:
				log_span_fatal( tk.span, "Expected 'decl' or a directive, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}
	}

	return false;
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
