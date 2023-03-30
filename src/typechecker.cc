#include "typechecker.hh"

#include "compiler.hh"
#include "profiling.hh"


static void import_data_from_child_module( Module* module, Module* sub_module )
{
	TIME_PROC();

	for ( auto& struct_decl : sub_module->structs )
	{
		TIME_SCOPE( "Import Structs" );

		if ( module->type_registry.find( struct_decl.name ) != module->type_registry.cend() )
			Compiler::panic( struct_decl.span, "Type '%s' is already defined in direct parent module: '%s'", struct_decl.name.c_str(), "DEV NEEDS TO ADD THIS, SORRY FOR THE BAD ERROR" );

		module->type_registry[struct_decl.name] = TY_STRUCT;
	}

	for ( auto& proc_decl : sub_module->procs )
	{
		TIME_SCOPE( "Import Procedures" );

		if ( module->proc_registry.find( proc_decl.name ) != module->proc_registry.cend() )
			Compiler::panic( proc_decl.span, "Procedure '%s' is already defined in child module: '%s'", proc_decl.name.c_str(), "DEV NEEDS TO ADD THIS, SORRY FOR THE BAD ERROR" );

		module->proc_registry[proc_decl.name] = &proc_decl;
	}
}


static void typecheck_block( Module* module, Block& block );


void typecheck_module( Module* module )
{
	TIME_PROC();

	for ( Module* module_dep : module->imports )
	{
		TIME_SCOPE( "Typecheck Child Modules" );
		typecheck_module( module_dep );

		import_data_from_child_module( module, module_dep );
	}

	for ( StructDeclStmnt& struct_decl : module->structs )
	{
		TIME_SCOPE( "Typecheck Structs" );

		for ( StructMember& member : struct_decl.members )
		{
			if ( member.type.kind != TY_UNKNOWN ) continue;

			if ( module->type_registry.find( member.type.name ) == module->type_registry.cend() )
				Compiler::panic( member.type.span, "Unknown typename: '%s'\n", member.type.name.c_str() );

			// FIXME: This isn't sufficient checking. Since some member's
			//        member could be the same type as the current.
			if ( member.type.kind != TY_PTR && member.type.name == struct_decl.name )
				Compiler::panic( member.type.span, "To have a sub-member the same type as the parent, it must be indirected. Consider making it a pointer." );

			member.type.kind = module->type_registry.at( member.type.name );
		}
	}

	// TODO: check enums and unions

	// TODO: check constants and globals

	for ( ProcDeclStmnt& proc_decl : module->procs )
	{
		TIME_SCOPE( "Pre-load Local Procedures" );

		// Pre-initialize the proc_registry with module-local procedures
		if ( module->proc_registry.find( proc_decl.name ) != module->proc_registry.cend() )
			Compiler::panic( proc_decl.span, "This procedure has already been defined" );

		module->proc_registry[proc_decl.name] = &proc_decl;
	}

	for ( ProcDeclStmnt& proc_decl : module->procs )
	{
		TIME_SCOPE( "Typecheck Local Procedures" );

		for ( auto& param : proc_decl.params )
		{
			if ( param.type.kind != TY_UNKNOWN ) continue;

			if ( module->type_registry.find( param.type.name ) == module->type_registry.cend() )
				Compiler::panic( param.type.span, "Unknown typename: '%s'", param.type.name.c_str() );

			param.type.kind = module->type_registry.at( param.type.name );
		}

		if ( proc_decl.return_type.kind == TY_UNKNOWN )
		{
			if ( module->type_registry.find( proc_decl.return_type.name ) == module->type_registry.cend() )
				Compiler::panic( proc_decl.return_type.span, "Unknown typename: '%s'", proc_decl.return_type.name.c_str() );

			proc_decl.return_type.kind = module->type_registry.at( proc_decl.return_type.name );
		}

		typecheck_block( module, proc_decl.body );
	}
}


static void typecheck_block( Module* module, Block& block )
{
	TIME_PROC();
}
