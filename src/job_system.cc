#include "job_system.hh"
#include <cassert>

#include "profiling.hh"

JobSystem* JobSystem::the = nullptr;

JobSystem::JobSystem()
	: queue_mutex()
	, state_update_cv()
	, is_working( false )
	, should_terminate( false )
	, workers()
	, jobs()
{
	assert( the == nullptr );

	the = this;
}

void JobSystem::start( size_t worker_count )
{
	the->workers.reserve( worker_count );

	for ( size_t i = 0; i < worker_count; i++ )
	{
		the->workers.push_back( std::thread( &JobSystem::worker_stub ) );
	}
}


void JobSystem::stop()
{
	{
		std::unique_lock<std::mutex> lock( the->queue_mutex );
		the->should_terminate = true;
	}

	the->state_update_cv.notify_all();

	for ( std::thread& thread : the->workers )
	{
		thread.join();
	}

	the->workers.clear();
}


void JobSystem::enqueue_job( CompileJob job )
{
	{
		std::unique_lock<std::mutex> lock( the->queue_mutex );
		the->jobs.push( job );
	}

	the->state_update_cv.notify_one();
}


bool JobSystem::is_busy()
{
	bool busy = false;

	{
		std::unique_lock<std::mutex> lock( the->queue_mutex );
		busy = !the->jobs.empty() || the->is_working;
	}

	return busy;
}


void JobSystem::worker_stub()
{
	for( ;; )
	{
		TIME_THREAD( "Worker" );
		CompileJob job;

		{
			TIME_SCOPE( "Worker::wait_for_job" );

			std::unique_lock<std::mutex> lock( the->queue_mutex );

			the->state_update_cv.wait( lock, [] ()
			{
				return !JobSystem::the->jobs.empty() || JobSystem::the->should_terminate;
			});

			if ( the->should_terminate )
				return;

			job = the->jobs.front();
			the->jobs.pop();

			the->is_working = true;
		}

		assert( job.module );
		job.proc( job.filepath, job.module );

		{
			TIME_SCOPE( "Worker::end_job" );

			std::unique_lock<std::mutex> lock( the->queue_mutex );

			the->is_working = false;
		}
	}
}
