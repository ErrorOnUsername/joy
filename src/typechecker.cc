#include "typechecker.hh"

Typechecker::Typechecker(Module&& root_mod, Arena&& expr_store, Arena&& stmnt_store)
	: root_module(std::move(root_mod))
	, expr_arena(std::move(expr_store))
	, stmnt_arena(std::move(stmnt_store))
{ }

void Typechecker::typecheck_root_module()
{
}
