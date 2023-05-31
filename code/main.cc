#include "compiler.hh"
#include "log.hh"
#include "profiling.hh"
#include "typechecker.hh"

static int exit_failed()
{
	while( Compiler_JobSystem_IsBusy() );
	Compiler_JobSystem_Terminate();

	printf( "\tCompilation \x1b[31;1mfailed\x1b[0m\n" );

	return 1;
}

static int exit_succeeded()
{
	while( Compiler_JobSystem_IsBusy() );
	if ( !Compiler_JobSystem_Terminate() ) return exit_failed();

	printf( "\tCompilation \x1b[32;1msucceeded\x1b[0m\n" );

	return 0;
}

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
		exited_with_error = Compiler_JobSystem_DidAnyWorkersFail() || !main_module;
	}

	if ( !main_module )
	{
		log_error( "Couldn't load the main module at path '%s'", "./test_files/test.df" );
	}

	if ( exited_with_error ) return exit_failed();


	{
		TIME_SCOPE( "build task queue & perform cycle check" );

		int level = 0;
		bool found_cycle = Typechecker_BuildTaskQueue( main_module, level );
		if ( found_cycle )
		{
			Typechecker_LogCycle();
		}

		exited_with_error = found_cycle;
	}

	if ( exited_with_error ) return exit_failed();

	exited_with_error = !Typechecker_CheckModule( main_module );

	if ( exited_with_error ) return exit_failed();

	if ( exited_with_error ) return exit_failed();
	else return exit_succeeded();
}
