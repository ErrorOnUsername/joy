#pragma once
#include <vector>

#include "arena.h"
#include "ast.h"
#include "token.h"

class Parser {
public:
	Parser(std::vector<Token>& token_stream);

	void parse_module();
	Stmnt* parse_statement();
	Expr* parse_expr(bool can_assign, bool allow_newlines);
	Expr* parse_operand();
	Type parse_raw_type();
	TypeID register_type(Type& type);

	std::vector<StructMember> parse_struct_members();
	std::vector<ProcParameter> parse_proc_decl_param_list();
	Block parse_stmnt_block();

	Token current();
	Token next();
	void eat_next_specific(TokenKind kind);
	void eat_current_specific(TokenKind kind);
	void eat_whitespace();

	Token peek(int64_t offset = 1);

private:
	std::vector<Token>& m_token_stream;
	size_t m_idx;
	size_t m_current_scope;

	Module m_root_module;
	Arena m_stmnt_arena;
	Arena m_expr_arena;
};
