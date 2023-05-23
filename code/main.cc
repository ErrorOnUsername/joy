#include "compiler.hh"
#include "profiling.hh"

int main()
{
	PROF_START_APP( "swarm" );
	TIME_MAIN();

	bool exited_with_error;
	{
		TIME_SCOPE( "lexing and parsing..." );

		int worker_count = 8;
		Compiler_JobSystem_Start( worker_count );

		Compiler_ScheduleLoad( "./test_files/test.df" );

		while ( Compiler_JobSystem_IsBusy() );
		exited_with_error = !Compiler_JobSystem_Terminate();
	}

	char const* status_str = "\x1b[32;1msucceeded\x1b[0m";
	if ( exited_with_error )
	{
		status_str = "\x1b[31;1mfailed\x1b[0m";
	}

	printf( "\tCompilation %s", status_str );
}
