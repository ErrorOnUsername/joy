#include <iostream>
#include <filesystem>
#include <vector>

#include "compiler.hh"
#include "lexer.hh"
#include "parser.hh"


int main()
{
	Compiler::init();

	Lexer lexer("test.df");

	std::vector<Token> token_stream;
	Token tk = lexer.next_tk();

	for (;;) {
		token_stream.push_back(tk);
		if (tk.kind == TK_EOF)
			break;
		tk = lexer.next_tk();
	}

	Parser parser(token_stream);
	parser.parse_module();

	return 0;
}
