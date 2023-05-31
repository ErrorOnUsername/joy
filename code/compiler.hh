#pragma once
#include <string>

#include "ast.hh"


Module* Compiler_FindOrAddModule( std::string const& path, bool& did_create );
Module* Compiler_ScheduleLoad( std::string const& path );

void Compiler_JobSystem_Start( int worker_count );
bool Compiler_JobSystem_Terminate();

bool Compiler_JobSystem_IsBusy();
bool Compiler_JobSystem_DidAnyWorkersFail();
