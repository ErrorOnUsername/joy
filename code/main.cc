#include "compiler.hh"
#include "log.hh"
#include "profiling.hh"
#include "typechecker.hh"

int main()
{
	PROF_START_APP( "swarm" );
	TIME_MAIN();

	Module* main_module;

	bool exited_with_error;
	{
		TIME_SCOPE( "lexing and parsing..." );

		int worker_count = 8;
		Compiler_JobSystem_Start( worker_count );

		main_module = Compiler_ScheduleLoad( "./test_files/test.df" );

		while ( Compiler_JobSystem_IsBusy() );
		exited_with_error = !Compiler_JobSystem_Terminate() || !main_module;
	}

	if ( !main_module )
	{
		log_error( "Couldn't load the main module at path '%s'", "./test_files/test.df" );
	}

	if ( !exited_with_error )
	{
		bool found_cycle = Typechecker_BuildTaskQueue( main_module );
		if ( found_cycle )
		{
			Typechecker_LogCycle();
		}

		exited_with_error = found_cycle;
	}

	if ( !exited_with_error )
	{
		exited_with_error = !Typechecker_CheckModule( main_module );
	}

	char const* status_str = "\x1b[32;1msucceeded\x1b[0m";
	if ( exited_with_error )
	{
		status_str = "\x1b[31;1mfailed\x1b[0m";
	}

	printf( "\tCompilation %s", status_str );
}
