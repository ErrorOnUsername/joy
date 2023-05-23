#pragma once
#include <string>


void Compiler_ScheduleLoad( std::string const& path );

void Compiler_JobSystem_Start( int worker_count );
bool Compiler_JobSystem_Terminate();

bool Compiler_JobSystem_IsBusy();
