#include "typechecker.hh"
#include <chrono>
#include <thread>
#include <vector>

#include "compiler.hh"
#include "log.hh"
#include "profiling.hh"


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


static void Typechecker_CheckModule( std::string const& path, Module* module );


bool Typechecker_StageAllTasks()
{
	TIME_PROC();

	size_t current_task_idx = 0;
	size_t current_task_group = 0;

	while ( current_task_idx < s_task_queue.size() )
	{
		Module* mod = s_task_queue[current_task_idx];
		while ( mod && mod->typechecker_task_group == current_task_group )
		{
			Job job;
			job.str  = mod->full_path;
			job.mod  = mod;
			job.proc = Typechecker_CheckModule;

			Compiler_ScheduleJob( job );

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


static void Typechecker_CheckScope( Module* module, Scope* scope );

static void Typechecker_CheckModule( std::string const& path, Module* module )
{
	TIME_PROC();

	// Make sure children have been properly typechecked
	for ( size_t i = 0; i < module->imports.count; i++ )
	{
		if ( !module->imports[i]->typechecker_complete )
		{
			log_fatal( "Child module was not properly typechecked!" );
		}
	}

	// Recurse through lexical scopes:
	//   1. Typecheck type definitions
	//   2. Typecheck constants
	//   3. Typecheck procedures
	//       - These do not inherit non-constant declarations from
	//         their parent scope, only the global scope
	//   4. Typecheck statements

	Typechecker_CheckScope( module, module->root_scope );

	module->typechecker_complete = true;
}


static void Typechecker_LookupTypeID( Scope* scope, Type* type )
{
	TIME_PROC();

	log_span_fatal( type->span, "TODO: Type lookup" );
}


static void Typechecker_CheckExpression( Scope* scope, AstNode* expr, Type* expected_type = nullptr )
{
	TIME_PROC();

	log_span_fatal( expr->span, "TODO: Expression checking" );
}


static void Typechecker_CheckStructDecl( Module* module, Scope* scope, size_t local_type_idx, StructDeclStmnt* decl )
{
	TIME_PROC();

	for ( size_t i = 0; i < decl->members.count; i++ )
	{
		VarDeclStmnt* member = decl->members[i];

		if ( member->type )
		{
			if ( member->type->name == decl->name )
			{
				log_span_fatal( member->type->span, "Cannot have a struct member with the same type without indirection. Consider making this a '*%s'", decl->name.c_str() );
			}

			Typechecker_LookupTypeID( scope, member->type );

			if ( member->type )
			{
				Typechecker_CheckExpression( scope, member->default_value, member->type );
			}
		}
		else
		{
			Typechecker_CheckExpression( scope, member->default_value );
		}

		if ( member->default_value && member->type && ( member->type->id != member->default_value->type->id ) )
		{
			// FIXME: #ERROR_CLEANUP
			log_span_fatal( member->span, "Struct member and expression are of incongruent types" );
		}
	}
}


static void Typechecker_CheckEnumDecl( Module* module, Scope* scope, size_t local_type_idx, EnumDeclStmnt* decl )
{
	TIME_PROC();

	log_span_fatal( decl->span, "TODO: Implement enum typechecking" );
}


static void Typechecker_CheckUnionDecl( Module* module, Scope* scope, size_t local_type_idx, UnionDeclStmnt* decl )
{
	TIME_PROC();

	log_span_fatal( decl->span, "TODO: Implement union typechecking" );
}


static void Typechecker_CheckScope( Module* module, Scope* scope )
{
	TIME_PROC();

	for ( size_t i = 0; i < scope->types.count; i++ )
	{
		AstNode* type_decl = scope->types[i];

		switch ( type_decl->kind )
		{
			case AstNodeKind::StructDecl: Typechecker_CheckStructDecl( module, scope, i, (StructDeclStmnt*)type_decl ); break;
			case AstNodeKind::EnumDecl:   Typechecker_CheckEnumDecl( module, scope, i, (EnumDeclStmnt*)type_decl ); break;
			case AstNodeKind::UnionDecl:  Typechecker_CheckUnionDecl( module, scope, i, (UnionDeclStmnt*)type_decl ); break;
			default:
				log_span_fatal( type_decl->span, "Internal typechecker error! Supposed type is of invalid kind '%d'", type_decl->kind );
		}
	}
}
