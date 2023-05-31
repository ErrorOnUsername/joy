#pragma once

#include "ast.hh"


bool Typechecker_BuildTaskQueue( Module* root_module, int& level );
void Typechecker_LogTaskQueue();
void Typechecker_LogCycle();
bool Typechecker_CheckModule( Module* module );
