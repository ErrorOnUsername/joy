#include "program.hh"
#include <cassert>
#include <filesystem>


Program* Program::the = nullptr;

Program::Program()
{
	assert( the == nullptr );
	Program::the = this;
}


Module* Program::add_module( std::string const& path )
{
	Program* the_program = Program::the;
	assert( the_program );

	std::string full_path = std::filesystem::absolute( path ).string();

	std::scoped_lock<std::mutex> lock( Program::the->module_mutex );

	assert( the_program->module_map.find( full_path ) == the_program->module_map.cend() );

	Module* mod = (Module*)the_program->module_arena.alloc_bytes( sizeof( Module ) );
	new (mod) Module(); // essentially zero-out the data

	the_program->module_map[full_path] = mod;

	return mod;
}


Module* Program::get_module( std::string const& path )
{
	Program* the_program = Program::the;
	assert( the_program );

	std::string full_path = std::filesystem::absolute( path ).string();

	std::scoped_lock<std::mutex> lock( Program::the->module_mutex );

	assert( the_program->module_map.find( full_path ) != the_program->module_map.cend() );

	return the_program->module_map.at( full_path );
}


Module* Program::get_or_add_module( std::string const& path )
{
	Program* the_program = Program::the;
	assert( the_program );

	std::string full_path = std::filesystem::absolute( path ).string();

	std::scoped_lock<std::mutex> lock( Program::the->module_mutex );

	Module* mod = nullptr;
	if ( the_program->module_map.find( full_path ) != the_program->module_map.cend() )
	{
		mod = the_program->module_map.at( full_path );
	}
	else
	{
		mod = (Module*)the_program->module_arena.alloc_bytes( sizeof( Module ) );
		new (mod) Module(); // essentially zero-out the data

		the_program->module_map[full_path] = mod;
	}

	assert( mod != nullptr );

	return mod;
}
