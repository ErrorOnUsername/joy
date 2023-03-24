#pragma once
#include <string>
#include <vector>

struct Module;
struct Span;

class Compiler {
public:
	static void init();
	static std::string const& filepath(size_t id);
	static std::string const& file_data(size_t id);
	static size_t open_file(std::string const& filepath);

	static void panic(Span span, char const* msg, ...);
	static void todo(char const* msg, ...);

	static void compile_module_job(std::string const& filepath, Module& module);

private:
	static Compiler* s_the;

	std::vector<std::string> m_file_data_registry;
	std::vector<std::string> m_filepath_registry;
};

#define TODO() \
	Compiler::todo("TODO[%s]: %s(%d)\n", __FUNCTION__, __FILE__, __LINE__);
