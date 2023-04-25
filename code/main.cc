#include "ast.hh"
#include "lexer.hh"
#include "parser.hh"

#include "profiling.hh"

int main()
{
	PROF_START_APP( "swarm" );
	TIME_MAIN();

	Parser parser;

	parser.process_module( "./test_files/test.df" );
}
