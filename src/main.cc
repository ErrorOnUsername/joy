#include <chrono>
#include <iostream>
#include <filesystem>
#include <thread>
#include <vector>

#include "compiler.hh"
#include "job_system.hh"
#include "lexer.hh"
#include "parser.hh"
#include "profiling.hh"
#include "program.hh"
#include "typechecker.hh"


using namespace std::chrono_literals;
using Time = std::chrono::high_resolution_clock;


int main()
{
	PROF_APP( "swarm" );
	TIME_MAIN();

	Program the_program;
	JobSystem the_job_system;
	Compiler::init();

	// Create the root module
	char const* path = "./test.df";
	Module* root = Program::add_module( path );

	CompileJob start_job = {
		.filepath = path,
		.module   = root,
		.proc     = Compiler::compile_module_job,
	};

	auto parse_start = Time::now();

	{
		TIME_SCOPE( "Lexing & Parsing" );
		// TODO: Command line arg "-j[n]"
		size_t worker_count = 8;
		JobSystem::start( worker_count );

		JobSystem::enqueue_job( start_job );

		while ( JobSystem::is_busy() );

		JobSystem::stop();
	}

	auto parse_end = Time::now();

	typecheck_module( root );

	std::chrono::duration<float> sec_duration = parse_end - parse_start;
	float secs = sec_duration.count();

	printf( "\n\tlexing & parsing: %.3fs\n", secs );

	printf( "\nCompilation \x1b[32;1msuccessful\x1b[0m!\n" );

	return 0;
}
