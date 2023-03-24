#include <chrono>
#include <iostream>
#include <filesystem>
#include <thread>
#include <vector>

#include "compiler.hh"
#include "job_system.hh"
#include "lexer.hh"
#include "parser.hh"
#include "program.hh"


using namespace std::chrono_literals;


int main()
{
	new Program();
	Compiler::init();

	// Create the root module
	char const* path = "./test.df";
	Module* root = Program::add_module(path);

	CompileJob start_job = {
		.filepath = path,
		.module   = root,
		.proc     = Compiler::compile_module_job,
	};

	// TODO: Command line arg "-j[n]"
	JobSystem job_system;

	size_t worker_count = 8;
	job_system.start(worker_count);

	job_system.enqueue_job(start_job);

	do {
		// FIXME: Is this too long? too short? test...
		std::this_thread::sleep_for(5ms);
	} while (job_system.is_busy());

	job_system.stop();

	printf("\nCompilation \x1b[32;1msuccessful\x1b[0m!\n");

	return 0;
}
