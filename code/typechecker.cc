#include "typechecker.hh"
#include <chrono>
#include <thread>
#include <vector>

#include "ast.hh"
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
		Module* child = root_module->imports[i]->module;

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
		if ( !module->imports[i]->module->typechecker_complete )
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


static TypeID Typechecker_GetPrimitiveID( TyKind kind )
{
	switch ( kind )
	{
		case TypeKind::PrimitiveNothing: return ReservedTypeID::PrimitiveNothing;
		case TypeKind::PrimitiveBool:    return ReservedTypeID::PrimitiveBool;
		case TypeKind::PrimitiveChar:    return ReservedTypeID::PrimitiveChar;
		case TypeKind::PrimitiveU8:      return ReservedTypeID::PrimitiveU8;
		case TypeKind::PrimitiveI8:      return ReservedTypeID::PrimitiveI8;
		case TypeKind::PrimitiveU16:     return ReservedTypeID::PrimitiveU16;
		case TypeKind::PrimitiveI16:     return ReservedTypeID::PrimitiveI16;
		case TypeKind::PrimitiveU32:     return ReservedTypeID::PrimitiveU32;
		case TypeKind::PrimitiveI32:     return ReservedTypeID::PrimitiveI32;
		case TypeKind::PrimitiveU64:     return ReservedTypeID::PrimitiveU64;
		case TypeKind::PrimitiveI64:     return ReservedTypeID::PrimitiveI64;
		case TypeKind::PrimitiveF32:     return ReservedTypeID::PrimitiveF32;
		case TypeKind::PrimitiveF64:     return ReservedTypeID::PrimitiveF64;
		case TypeKind::PrimitiveRawPtr:  return ReservedTypeID::PrimitiveRawPtr;
		case TypeKind::PrimitiveString:  return ReservedTypeID::PrimitiveString;
		case TypeKind::PrimitiveCString: return ReservedTypeID::PrimitiveCString;
		default: log_fatal( "Internal compiler error! Unknown primitive type kind '%u'", kind );
	}
}


static std::string const& Typechecker_GetName( AstNode* type_decl )
{
	switch ( type_decl->kind )
	{
		case AstNodeKind::StructDecl: return ((StructDeclStmnt*)type_decl)->name;
		case AstNodeKind::EnumDecl:   return ((EnumDeclStmnt*)type_decl)->name;
		case AstNodeKind::UnionDecl:  return ((UnionDeclStmnt*)type_decl)->name;
		default:
			log_span_fatal( type_decl->span, "Internal compiler error! Tried to get name of type with invalid kind '%u'", type_decl->kind );
	}
}


static void Typechecker_CheckType( Module* module, Scope* scope, size_t local_type_idx, AstNode* decl_node );


static void Typechecker_LookupTypeID( Module* module, Scope* scope, Type* type )
{
	TIME_PROC();

	if ( type->kind & TypeKind::Primitive )
	{
		type->id = Typechecker_GetPrimitiveID( type->kind );
		return;
	}

	bool is_aliased = !type->import_alias.empty();

	if ( !is_aliased )
	{
		for ( size_t i = 0; i < scope->types.count; i++ )
		{
			AstNode* type_decl = scope->types[i];
			std::string const& name = Typechecker_GetName( type_decl );
			if ( type->name != name ) continue;

			if ( type_decl->type_id == ReservedTypeID::Unknown )
			{
				Typechecker_CheckType( module, scope, i, type_decl );
			}

			type->id = type_decl->type_id;
			return;
		}
	}


	for ( size_t i = 0; i < module->imports.count; i++ )
	{
		LoadStmnt* import = module->imports[i];
		if ( is_aliased && type->import_alias != import->alias ) continue;

		Scope* import_root_scope = import->module->root_scope;

		for ( size_t j = 0; j < import_root_scope->types.count; j++ )
		{
			AstNode* type_decl = import_root_scope->types[i];
			std::string const& name = Typechecker_GetName( type_decl );
			if ( type->name != name ) continue;

			type->id = type_decl->type_id;
			return;
		}

		log_span_fatal( type->span, "Could not find type '%s' from module with import alias '%s'", type->name.c_str(), type->import_alias.c_str() );
	}

	log_span_fatal( type->span, "Unkown type name '%s'", type->name.c_str() );
}


static bool Typechecker_DoesIntFitInType( IntegerLiteralExpr* literal, Type* type )
{
	switch ( type->kind )
	{
		case TypeKind::PrimitiveU8:
		case TypeKind::PrimitiveI8:
			return literal->data <= 0xff;
		case TypeKind::PrimitiveU16:
		case TypeKind::PrimitiveI16:
			return literal->data <= 0xffff;
		case TypeKind::PrimitiveU32:
		case TypeKind::PrimitiveI32:
			return literal->data <= 0xffffffff;
		case TypeKind::PrimitiveU64:
		case TypeKind::PrimitiveI64:
			return literal->data <= 0xffffffffffffffff;
		case TypeKind::PrimitiveUSize:
		case TypeKind::PrimitiveISize:
			// TODO: #TARGET_PLATFORM_CHECK
			return literal->data <= 0xffffffffffffffff;
	}

	return false;
}


static void Typechecker_CheckExpression( Scope* scope, AstNode* expr, Type* expected_type = nullptr )
{
	TIME_PROC();

	log_span_fatal( expr->span, "TODO: Expression checking" );
}


static void Typechecker_CheckStructDecl( Module* module, Scope* scope, size_t local_type_idx, StructDeclStmnt* decl )
{
	TIME_PROC();

	for ( int64_t i = local_type_idx - 1; i >= 0; i-- )
	{
		AstNode* other_type = scope->types[i];
		std::string const& other_name = Typechecker_GetName( other_type );

		if ( other_name == decl->name )
		{
			// TODO: #ERROR_CLEANUP
			log_span_fatal( decl->span, "Duplicate definitions of type '%s' in the same lexical scope", decl->name.c_str() );
		}
	}

	for ( size_t i = 0; i < decl->members.count; i++ )
	{
		VarDeclStmnt* member = decl->members[i];

		if ( member->type )
		{
			if ( member->type->name == decl->name )
			{
				log_span_fatal( member->type->span, "Cannot have a struct member with the same type without indirection. Consider making this a '*%s'", decl->name.c_str() );
			}

			Typechecker_LookupTypeID( module, scope, member->type );

			if ( member->default_value )
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

	for ( int64_t i = local_type_idx - 1; i >= 0; i-- )
	{
		AstNode* other_type = scope->types[i];
		std::string const& other_name = Typechecker_GetName( other_type );

		if ( other_name == decl->name )
		{
			// TODO: #ERROR_CLEANUP
			log_span_fatal( decl->span, "Duplicate definitions of type '%s' in the same lexical scope", decl->name.c_str() );
		}
	}

	for ( size_t i = 0; i < decl->variants.count; i++ )
	{
		EnumVariant& variant = decl->variants[i];

		if ( !Typechecker_DoesIntFitInType( variant.val, decl->type ) )
		{
			log_span_fatal( variant.span, "Enum variant value does not fit within underlying type '%s'", decl->type->name.c_str() );
		}
	}
}


static void Typechecker_CheckUnionDecl( Module* module, Scope* scope, size_t local_type_idx, UnionDeclStmnt* decl )
{
	TIME_PROC();

	for ( int64_t i = local_type_idx - 1; i >= 0; i-- )
	{
		AstNode* other_type = scope->types[i];
		std::string const& other_name = Typechecker_GetName( other_type );

		if ( other_name == decl->name )
		{
			// TODO: #ERROR_CLEANUP
			log_span_fatal( decl->span, "Duplicate definitions of type '%s' in the same lexical scope", decl->name.c_str() );
		}
	}

	for ( size_t i = 0; i < decl->variants.count; i++ )
	{
		UnionVariant& variant = decl->variants[i];

		for ( size_t j = 0; j < variant.members.count; j++ )
		{
			AstNode* member = variant.members[j];

			Typechecker_LookupTypeID( module, scope, member->type );
		}
	}
}


static void Typechecker_CheckType( Module* module, Scope* scope, size_t local_type_idx, AstNode* decl_node )
{
	switch ( decl_node->kind )
	{
		case AstNodeKind::StructDecl: Typechecker_CheckStructDecl( module, scope, local_type_idx, (StructDeclStmnt*)decl_node ); break;
		case AstNodeKind::EnumDecl:   Typechecker_CheckEnumDecl( module, scope, local_type_idx, (EnumDeclStmnt*)decl_node ); break;
		case AstNodeKind::UnionDecl:  Typechecker_CheckUnionDecl( module, scope, local_type_idx, (UnionDeclStmnt*)decl_node ); break;
		default:
			log_span_fatal( decl_node->span, "Internal typechecker error! Supposed type is of invalid kind '%d'", decl_node->kind );
	}
}


static void Typechecker_CheckProcedureDecl( Module* module, Scope* scope, ProcDeclStmnt* decl )
{
	TIME_PROC();

	log_span_fatal( decl->span, "Implement procedure typechecking" );
}


static void Typechecker_CheckStatementList( Module* module, Scope* scope )
{
	TIME_PROC();

	for ( size_t i = 0; i < scope->statements.count; i++ )
	{
		AstNode* stmnt = scope->statements[0];

		log_span_fatal( stmnt->span, "Implement statement typechecking" );
	}
}


static void Typechecker_CheckScope( Module* module, Scope* scope )
{
	TIME_PROC();

	for ( size_t i = 0; i < scope->types.count; i++ )
	{
		AstNode* type_decl = scope->types[i];
		Typechecker_CheckType( module, scope, i, type_decl );
	}

	Typechecker_CheckStatementList( module, scope );

	for ( size_t i = 0; i < scope->procedures.count; i++ )
	{
		Typechecker_CheckProcedureDecl( module, scope, scope->procedures[i] );
	}
}
