#include "lexer.hh"
#include "ast.hh"

int main()
{
	FileLexInfo lex_info = FileManager_GetOrCreateFileInfo( "./test_files/test.df" );

	Token tk = Lexer_GetNextToken( lex_info );
	do {
		printf( "tk: %s ", Token_GetKindAsString( tk.kind ) );
		if ( tk.kind == TK::Ident )
		{
			printf( "(%s)", tk.str.c_str() );
		}
		else if ( tk.kind == TK::Number )
		{
			if ( tk.number.kind == NumKind::Integer )
			{
				printf( "(%zu)", tk.number.inum );
			}
			else if ( tk.number.kind == NumKind::FloatingPoint )
			{
				printf( "(%f)", tk.number.fnum );
			}
		}
		else if ( tk.kind == TK::StringLiteral )
		{
			printf( "(\"%s\")", tk.str.c_str() );
		}
		printf( "\n" );

		tk = Lexer_GetNextToken( lex_info );
	} while( tk.kind != TK::EndOfFile );
}
