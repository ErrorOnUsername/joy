#include <iostream>
#include <filesystem>
#include <vector>

#include "compiler.hh"
#include "lexer.hh"
#include "parser.hh"


int main()
{
	Compiler::init();

	char const* file_path = "test.df";
	Lexer lexer(file_path);

	std::vector<Token> token_stream;
	Token tk = lexer.next_tk();

	for (;;) {
		token_stream.push_back(tk);
		if (tk.kind == TK_DOT)
			printf("%s, %lld - %lld\n", tk_as_str(tk.kind), tk.span.start_idx, tk.span.end_idx);
		if (tk.kind == TK_EOF)
			break;
		tk = lexer.next_tk();
	}

	Parser parser(token_stream);
	parser.parse_module();

	printf("\nCompilation \x1b[32;1msuccessful\x1b[0m!\n");

	return 0;
}
