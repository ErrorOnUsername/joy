#pragma once
#include <cstdint>
#include <mutex>
#include <unordered_map>

#include "ast.hh"

struct Program {
	static Program* the;

	std::mutex                                module_mutex;
	std::vector<Module>                       modules;
	std::unordered_map<std::string, ModuleID> module_map;

	Program();

	static Module* add_module(std::string const& path);
	static Module* get_module(std::string const& path);
	static Module* get_or_add_module(std::string const& path);
};
