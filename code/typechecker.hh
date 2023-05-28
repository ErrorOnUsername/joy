#pragma once

#include "ast.hh"


bool Typechecker_BuildTaskQueue( Module* root_module );
void Typechecker_LogCycle();
bool Typechecker_CheckModule( Module* module );
