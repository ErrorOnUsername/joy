#pragma once
#include <condition_variable>
#include <mutex>
#include <queue>
#include <string>
#include <thread>

struct Module;

using CompileModuleProc = void(*)(std::string const& filepath, Module& module);

struct CompileJob {
	std::string       filepath;
	Module*           module;
	CompileModuleProc proc;
};

struct JobSystem {
	std::mutex               queue_mutex;
	std::condition_variable  state_update_cv;
	bool                     should_terminate;
	std::vector<std::thread> workers;
	std::queue<CompileJob>   jobs;

	void start(size_t worker_count);
	void stop();

	void enqueue_job(CompileJob job);
	bool is_busy();

	void worker_stub();
};
