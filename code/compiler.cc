#include "compiler.hh"
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>
#ifdef _WIN32
#include <windows.h>
#include <processthreadsapi.h>
#else
#include <pthread.h>
#endif

#include "parser.hh"
#include "profiling.hh"


static std::vector<std::thread> s_workers;
static std::mutex s_job_queue_mutex;
static std::condition_variable s_job_status_update;
static std::queue<std::string> s_load_jobs;

static bool s_should_terminate = false;
static bool s_is_working       = false;

static int s_terminated_threads = 0;


static void Compiler_TerminationHandler()
{
	{
		std::unique_lock<std::mutex> lock ( s_job_queue_mutex );
		s_is_working = false;
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

			s_is_working = true;
		}

		{
			Parser parser;

			Module mod = parser.process_module( path );
		}

		{
			TIME_SCOPE( "ending task..." );

			std::unique_lock<std::mutex> lock( s_job_queue_mutex );

			s_is_working = false;
		}
	}
}


void Compiler_ScheduleLoad( std::string const& path )
{
	TIME_PROC();

	{
		std::unique_lock<std::mutex> lock( s_job_queue_mutex );
		s_load_jobs.push( path );
	}

	s_job_status_update.notify_one();
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

	return s_terminated_threads == 0;
}


bool Compiler_JobSystem_IsBusy()
{
	std::unique_lock<std::mutex> lock( s_job_queue_mutex );

	return !s_load_jobs.empty() || s_is_working;
}
