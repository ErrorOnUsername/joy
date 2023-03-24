#include "program.hh"
#include <cassert>
#include <filesystem>


Program* Program::the = nullptr;

Program::Program()
{
	assert(the == nullptr);
	Program::the = this;
}


Module* Program::add_module(std::string const& path)
{
	Program* the_program = Program::the;
	assert(the_program);

	std::string full_path = std::filesystem::absolute(path);

	std::scoped_lock<std::mutex> lock(Program::the->module_mutex);

	assert(the_program->module_map.find(full_path) == the_program->module_map.cend());

	ModuleID id = the_program->modules.size();

	the_program->modules.push_back(Module {});
	the_program->module_map[full_path] = id;
	return &Program::the->modules[id];
}


Module* Program::get_module(std::string const& path)
{
	Program* the_program = Program::the;
	assert(the_program);

	std::string full_path = std::filesystem::absolute(path);

	std::scoped_lock<std::mutex> lock(Program::the->module_mutex);

	assert(the_program->module_map.find(full_path) != the_program->module_map.cend());

	ModuleID id = the_program->module_map.at(full_path);
	return &Program::the->modules[id];
}


Module* Program::get_or_add_module(std::string const& path)
{
	Program* the_program = Program::the;
	assert(the_program);

	std::string full_path = std::filesystem::absolute(path);

	std::scoped_lock<std::mutex> lock(Program::the->module_mutex);

	ModuleID id = -1;

	if (the_program->module_map.find(full_path) != the_program->module_map.cend())
	{
		id = the_program->module_map.at(full_path);
	}
	else
	{
		id = the_program->modules.size();

		the_program->modules.push_back(Module {});
		the_program->module_map[full_path] = id;
	}

	return &Program::the->modules[id];
}
