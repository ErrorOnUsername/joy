#pragma once

#include "token.hh"

class Lexer
{
public:
	Lexer( std::string const& filepath );

	Token next_tk();
	Token tokenize_number();
	Token tokenize_ident();
	Token tokenize_directive();
	Token tokenize_char_literal();
	Token tokenize_string_literal();

	char current();
	char peek( int64_t offset = 1 );

	bool at_eof();

private:
	size_t m_file_id;
	std::string m_file_data;
	int64_t m_idx;
	int64_t m_line;
};
