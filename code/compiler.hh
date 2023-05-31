#pragma once
#include <string>

#include "ast.hh"


using JobCallback = void (*) ( std::string const&, Module* );

struct Job {
	std::string str;
	Module*     mod;
	JobCallback proc;
};


Module* Compiler_FindOrAddModule( std::string const& path, bool& did_create );
Module* Compiler_ScheduleLoad( std::string const& path );
void Compiler_ScheduleJob( Job const& path );

void Compiler_JobSystem_Start( int worker_count );
bool Compiler_JobSystem_Terminate();

bool Compiler_JobSystem_IsBusy();
bool Compiler_JobSystem_DidAnyWorkersFail();
