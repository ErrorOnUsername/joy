#include "job_system.hh"


void JobSystem::start(size_t worker_count)
{
	workers.reserve(worker_count);

	for (size_t i = 0; i < worker_count; i++) {
		workers[i] = std::thread(&JobSystem::worker_stub, this);
	}
}


void JobSystem::stop()
{
	{
		std::unique_lock<std::mutex> lock(queue_mutex);
		should_terminate = true;
	}

	state_update_cv.notify_all();

	for (std::thread& thread : workers) {
		thread.join();
	}

	workers.clear();
}


void JobSystem::enqueue_job(CompileJob job)
{
	printf("*****\n");
	{
		std::unique_lock<std::mutex> lock(queue_mutex);
		jobs.push(job);
	}

	state_update_cv.notify_one();
}


bool JobSystem::is_busy()
{
	bool busy = false;

	{
		std::unique_lock<std::mutex> lock(queue_mutex);
		busy = !jobs.empty();
	}

	return busy;
}


void JobSystem::worker_stub()
{
	for(;;) {
		CompileJob job;

		{
			std::unique_lock<std::mutex> lock(queue_mutex);

			state_update_cv.wait(lock, [this] () {
				return !jobs.empty() || should_terminate;
			});

			if (should_terminate)
				return;

			job = jobs.front();
			jobs.pop();
		}

		assert(job.module);
		job.proc(job.filepath, *job.module);
	}
}
