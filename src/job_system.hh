#pragma once
#include <condition_variable>
#include <mutex>
#include <queue>
#include <string>
#include <thread>

struct Module;

using CompileModuleProc = void(*)( std::string const& filepath, Module* module_id );

struct CompileJob
{
	std::string       filepath;
	Module*           module;
	CompileModuleProc proc;
};

struct JobSystem
{
	static JobSystem* the;

	std::mutex               queue_mutex;
	std::condition_variable  state_update_cv;
	bool                     should_terminate;
	std::vector<std::thread> workers;
	std::queue<CompileJob>   jobs;

	JobSystem();

	static void start( size_t worker_count );
	static void stop();

	static void enqueue_job( CompileJob job );
	static bool is_busy();

	static void worker_stub();
};
