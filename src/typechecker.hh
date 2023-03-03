#pragma once

#include "arena.hh"
#include "ast.hh"

struct Typechecker {
	Module root_module;
	Arena  expr_arena;
	Arena  stmnt_arena;

	Typechecker(Module&& root_mod, Arena&& expr_store, Arena&& stmnt_sore);

	void typecheck_root_module();
};
