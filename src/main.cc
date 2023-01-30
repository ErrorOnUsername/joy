#include <iostream>
#include <filesystem>
#include <vector>

#include "compiler.h"
#include "lexer.h"
#include "parser.h"


int main()
{
	Compiler::init();

	Lexer lexer("test.amds");

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