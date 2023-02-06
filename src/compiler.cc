#include "compiler.hh"
#include <cassert>
#include <cstdarg>
#include <cstdio>
#include <unistd.h>
#include <fstream>
#include <iostream>

#include "token.hh"

Compiler* Compiler::s_the = nullptr;

void Compiler::init()
{
	s_the = new Compiler();
}

size_t Compiler::open_file(std::string const& filepath)
{
	FILE* file = fopen(filepath.c_str(), "r");
	assert(file);

	fseek(file, 0, SEEK_END);
	size_t f_size = ftell(file);
	rewind(file);

	char* temp = (char*)malloc(f_size);
	assert(temp);
	memset(temp, 0, f_size);

	fread(temp, 1, f_size, file);

	std::string buf(temp);

	free(temp);
	fclose(file);

	s_the->m_file_data_registry.push_back(std::move(buf));
	return s_the->m_file_data_registry.size() - 1;
}

std::string const& Compiler::file_data(size_t id)
{
	return s_the->m_file_data_registry[id];
}

void Compiler::panic(Span span, char const* msg, ...)
{
	va_list args;
	va_start(args, msg);

	printf("Span: [%lld - %lld)\n", span.start_idx, span.end_idx);
	printf("\x1b[31;1m");
	vprintf(msg, args);
	printf("\x1b[0m\n");

	size_t line_start = span.start_idx;
	size_t line_end = span.end_idx;

	std::string const& file_data = s_the->m_file_data_registry[span.file_id];

	for (; line_start > 0; line_start--) {
		if (file_data[line_start] == '\n') {
			line_start++;
			break;
		}
	}

	for (; line_end < file_data.size(); line_end++) {
		if (file_data[line_end] == '\n')
			break;
	}

	size_t line_size = line_end - line_start;

	printf("%4lld| %s\n", span.line, file_data.substr(line_start, line_size).c_str());
	// FIXME: In the future, get the width of the number
	printf("      ");
	for (size_t i = line_start; i < line_end; i++) {
		if (i >= (size_t)span.start_idx && i < (size_t)span.end_idx)
			printf("^");
		else
			printf(file_data[i] == '\t' ? "\t" : " ");
	}
	printf("\n");

	va_end(args);

	exit(1);
}

void Compiler::todo(char const* msg, ...)
{
	va_list args;
	va_start(args, msg);

	printf("\x1b[33;1m");
	vprintf(msg, args);
	printf("\x1b[0m\n");

	exit(1);
}
