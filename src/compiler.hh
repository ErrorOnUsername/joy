#pragma once
#include <string>
#include <vector>

#define TODO() \
	Compiler::todo("TODO[%s]: %s(%d)\n", __FUNCTION__, __FILE__, __LINE__);

struct Span;

class Compiler {
public:
	static void init();
	static std::string const& file_data(size_t id);
	static size_t open_file(std::string const& filepath);

	static void panic(Span span, char const* msg, ...);
	static void todo(char const* msg, ...);

private:
	static Compiler* s_the;

	std::vector<std::string> m_file_data_registry;
};