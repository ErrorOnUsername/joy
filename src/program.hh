#pragma once
#include <cstdint>
#include <mutex>
#include <unordered_map>

#include "ast.hh"

struct Program
{
	static Program* the;

	std::mutex                               module_mutex;
	Arena                                    module_arena;
	std::unordered_map<std::string, Module*> module_map;

	Program();

	static Module* add_module( std::string const& path );
	static Module* get_module( std::string const& path );
	static Module* get_or_add_module( std::string const& path );
};
