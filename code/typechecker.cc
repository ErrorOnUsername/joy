#include "typechecker.hh"
#include <chrono>
#include <thread>
#include <vector>

#include "log.hh"
#include "compiler.hh"


std::vector<Module*> s_cycle_check_include_path;
std::vector<Module*> s_task_queue;


bool Typechecker_BuildTaskQueue( Module* root_module, int& level )
{
	//
	// This essentially is just a DFS to build the task queue,
	// but we also do a cycle check, so we can ensure that the
	// include graph is a DAG, since the way we'll multithread
	// typechecking relies on there being no cycles. Not to
	// mention, DFS would just overflow the stack if there were
	// any cycles.
	//


	s_cycle_check_include_path.push_back( root_module );
	for ( size_t i = 0; i < s_cycle_check_include_path.size(); i++ )
	{
		// This is probably faster than hashing (assuming
		// imports aren't that deep, which they shouldn't
		// for most sane codebases)

		Module* path_node = s_cycle_check_include_path[i];
		if ( path_node == root_module && i != s_cycle_check_include_path.size() - 1 ) return true;
	}

	for ( size_t i = 0; i < root_module->imports.count; i++ )
	{
		Module* child = root_module->imports[i];

		if ( level > 0 ) level--;
		if ( Typechecker_BuildTaskQueue( child, level ) ) return true;
	}

	root_module->typechecker_task_group = level;

	s_task_queue.push_back( root_module );
	s_cycle_check_include_path.pop_back();
	level++;

	return false;
}


void Typechecker_LogTaskQueue()
{
	std::string output_str = "[ ";

	for ( size_t i = 0; i < s_task_queue.size(); i++ )
	{
		Module* module = s_task_queue[i];

		size_t last_slash_pos = module->full_path.find_last_of( "/\\" );
		if ( last_slash_pos == std::string::npos )
		{
			last_slash_pos = 0;
		}

		output_str += module->full_path.substr( last_slash_pos + 1 );

		char temp_buff[64];
		sprintf( temp_buff, " (%zu)", module->typechecker_task_group );
		output_str += temp_buff;

		if ( i == ( s_task_queue.size() - 1 ) )
		{
			output_str += " ]";
		}
		else
		{
			output_str += ", ";
		}
	}

	log_info( "Task queue: %s", output_str.c_str() );
}


void Typechecker_LogCycle()
{
	std::string output_str = "[ ";

	for ( size_t i = 0; i < s_cycle_check_include_path.size(); i++ )
	{
		Module* module = s_cycle_check_include_path[i];

		size_t last_slash_pos = module->full_path.find_last_of( "/\\" );
		if ( last_slash_pos == std::string::npos )
		{
			last_slash_pos = 0;
		}

		output_str += module->full_path.substr( last_slash_pos + 1 );
		if ( i == ( s_cycle_check_include_path.size() - 1 ) )
		{
			output_str += " ]";
		}
		else
		{
			output_str += " -> ";
		}
	}

	log_error( "Found inclusion cycle: %s", output_str.c_str() );
}


bool Typechecker_StageAllTasks()
{
	size_t current_task_idx = 0;
	size_t current_task_group = 0;

	while ( current_task_idx < s_task_queue.size() )
	{
		Module* mod = s_task_queue[current_task_idx];
		while ( mod && mod->typechecker_task_group == current_task_group )
		{
			// TODO: Enqueue the job

			current_task_idx++;
			if ( current_task_idx >= s_task_queue.size() )
			{
				mod = nullptr;
			}
			else
			{
				mod = s_task_queue[current_task_idx];
			}
		}

		while( Compiler_JobSystem_IsBusy() );

		if ( Compiler_JobSystem_DidAnyWorkersFail() )
		{
			return false;
		}

		current_task_group++;
	}

	return true;
}


bool Typechecker_CheckModule( Module* module )
{
	std::this_thread::sleep_for( std::chrono::milliseconds( 2 ) );
	return true;
}
