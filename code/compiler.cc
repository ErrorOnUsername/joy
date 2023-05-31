#include "compiler.hh"
#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <queue>
#include <sys/stat.h>
#include <thread>
#include <unordered_map>
#ifdef _WIN32
#include <windows.h>
#include <processthreadsapi.h>
#else
#include <pthread.h>
#endif

#include "arena.hh"
#include "parser.hh"
#include "profiling.hh"


static std::vector<std::thread> s_workers;
static std::mutex s_job_queue_mutex;
static std::condition_variable s_job_status_update;
static std::queue<std::string> s_load_jobs;

static bool s_should_terminate = false;

static int s_working_threads    = 0;
static int s_terminated_threads = 0;

static std::mutex s_module_graph_mutex;
static Arena s_module_arena( 16 * 1024 );
static std::unordered_map<std::string, Module*> s_module_map;


Module* Compiler_FindOrAddModule( std::string const& path, bool& did_create )
{
	did_create = false;

	std::error_code abs_err;
	std::filesystem::path abs_path = std::filesystem::absolute( path, abs_err );
	if ( abs_err )
	{
		return nullptr;
	}

	std::string abs_path_str = abs_path.string();

	struct stat stat_res;
	int stat_code = stat( abs_path_str.c_str(), &stat_res );

	if ( stat_code != 0 || ( stat_res.st_mode & S_IFDIR ) )
	{
		return nullptr;
	}


	std::unique_lock<std::mutex> lock( s_module_graph_mutex );

	if ( s_module_map.find( abs_path_str ) != s_module_map.cend() )
	{
		return s_module_map[abs_path_str];
	}

	Module* mod = s_module_arena.alloc<Module>();
	mod->full_path = abs_path_str;

	s_module_map[abs_path_str] = mod;

	did_create = true;
	return mod;
}


static void Compiler_TerminationHandler()
{
	{
		std::unique_lock<std::mutex> lock ( s_job_queue_mutex );
		s_working_threads--;
		s_terminated_threads++;
	}

	int exit = 1;
#ifdef _WIN32
	ExitThread( exit );
#else
	pthread_exit( &exit );
#endif
}


static void JobSystem_WorkerProc( int worker_id )
{
	std::set_terminate( Compiler_TerminationHandler );

	char name[256] = { };
	std::sprintf( name, "Worker %d", worker_id );

	for ( ;; )
	{
		TIME_THREAD( name );

		std::string path;

		{
			TIME_SCOPE( "waiting for work..." );

			std::unique_lock<std::mutex> lock( s_job_queue_mutex );

			s_job_status_update.wait( lock, []()
			{
				return !s_load_jobs.empty() || s_should_terminate;
			});

			if ( s_should_terminate )
			{
				return;
			}

			path = s_load_jobs.front();
			s_load_jobs.pop();

			s_working_threads++;
		}

		{
			Parser parser;
			parser.process_module( path );
		}

		{
			TIME_SCOPE( "ending task..." );

			std::unique_lock<std::mutex> lock( s_job_queue_mutex );

			s_working_threads--;
		}
	}
}


Module* Compiler_ScheduleLoad( std::string const& path )
{
	TIME_PROC();

	bool created;
	Module* mod = Compiler_FindOrAddModule( path, created );
	if ( !mod ) return nullptr;
	if ( !created ) return mod;

	{
		std::unique_lock<std::mutex> lock( s_job_queue_mutex );
		s_load_jobs.push( path );
	}

	s_job_status_update.notify_one();

	return mod;
}


void Compiler_JobSystem_Start( int worker_count )
{
	TIME_PROC();

	for ( int i = 0; i < worker_count; i++ )
	{
		s_workers.push_back( std::move( std::thread( JobSystem_WorkerProc, i ) ) );
	}
}


bool Compiler_JobSystem_Terminate()
{
	TIME_PROC();

	if ( s_workers.size() == 0 ) return 0;

	{
		std::unique_lock<std::mutex> lock( s_job_queue_mutex );
		s_should_terminate = true;
	}

	s_job_status_update.notify_all();

	for ( std::thread& thread : s_workers )
	{
		if ( thread.joinable() )
		{
			thread.join();
		}
	}

	s_workers.clear();

	return s_terminated_threads == 0;
}


bool Compiler_JobSystem_IsBusy()
{
	std::unique_lock<std::mutex> lock( s_job_queue_mutex );

	return !s_load_jobs.empty() || s_working_threads > 0;
}


bool Compiler_JobSystem_DidAnyWorkersFail()
{
	return s_terminated_threads > 0;
}
