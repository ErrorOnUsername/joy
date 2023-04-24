#pragma once
#include <string>
#include <vector>

#include "arena.hh"
#include "ast.hh"
#include "file_manager.hh"
#include "lexer.hh"
#include "program.hh"
#include "token.hh"


struct Parser {
	size_t             tk_idx = 0;
	FileLexInfo        lex_info;
	std::vector<Token> seen_tokens;
	Arena              node_arena;
	Scope*             current_scope;

	Parser();

	Module process_module( std::string const& path );

	void parse_decl_stmnt();
	void parse_let_stmnt();

	void consume_newlines();

	Token& peek_tk( int offset = 1 );
	Token& curr_tk();
	Token& next_tk();
};
