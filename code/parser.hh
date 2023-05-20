#pragma once
#include <string>
#include <vector>

#include "array.hh"
#include "arena.hh"
#include "ast.hh"
#include "file_manager.hh"
#include "lexer.hh"
#include "program.hh"
#include "token.hh"


struct Parser {
	size_t             tk_idx = 0;
	FileLexInfo        lex_info;
	// FIXME: Allocate these in an arena, rather than a vector
	//        so we avoid expesive re-allocing.
	//
	// Also, we should return tokens by reference so that
	// we don't make stack copies all the time (expensive
	// since each token holds a std::string)
	std::vector<Token> seen_tokens;
	Arena              node_arena;
	Arena              type_arena;
	Scope*             current_scope;

	Parser();

	Module process_module( std::string const& path );

	void parse_decl_stmnt();
	void parse_let_stmnt();

	void parse_if_stmnt();
	void parse_for_stmnt();
	void parse_while_stmnt();
	void parse_loop_stmnt();
	void parse_continue_stmnt();
	void parse_break_stmnt();
	void parse_return_stmnt();

	void parse_constant_decl();
	void parse_procedure_decl();
	void parse_struct_decl();
	void parse_enum_decl();
	void parse_union_decl();

	VarDeclStmnt* parse_var_decl( char const* usage_in_str );
	AstNode* parse_expr( bool can_construct = false, bool can_assign = false );
	AstNode* parse_operand( bool can_construct );

	Type* parse_type();

	void consume_newlines();

	Token peek_tk( int offset = 1 );
	Token curr_tk();
	Token next_tk();
};
