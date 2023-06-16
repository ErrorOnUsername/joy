#include "log.hh"
#include <cstdio>
#include <cstdarg>
#include <mutex>

#ifdef _WIN32
#include <windows.h>
#include <debugapi.h>
#endif

#include "file_manager.hh"

#define ANSI_ESC_RESET  "\x1b[0m"
#define ANSI_ESC_RED    "\x1b[31;1m"
#define ANSI_ESC_YELLOW "\x1b[33;1m"

static std::mutex s_logging_mutex;

void log_info( char const* msg, ... )
{
	va_list va_args;
	va_start( va_args, msg );

	{
		std::scoped_lock<std::mutex> lock( s_logging_mutex );

		vprintf( msg, va_args );
		printf( "\n" );
	}

	va_end( va_args );
}


void log_warn( char const* msg, ... )
{
	va_list va_args;
	va_start( va_args, msg );

	{
		std::scoped_lock<std::mutex> lock( s_logging_mutex );

		printf( ANSI_ESC_YELLOW "Warning: " ANSI_ESC_RESET );
		vprintf( msg, va_args );
		printf( "\n" );
	}

	va_end( va_args );
}


void log_error( char const* msg, ... )
{
	va_list va_args;
	va_start( va_args, msg );

	{
		std::scoped_lock<std::mutex> lock( s_logging_mutex );

		printf( ANSI_ESC_RED "Error: " ANSI_ESC_RESET );
		vprintf( msg, va_args );
		printf( "\n" );
	}

	va_end( va_args );
}


[[noreturn]]
void log_fatal( char const* msg, ... )
{
	va_list va_args;
	va_start( va_args, msg );

	{
		std::scoped_lock<std::mutex> lock( s_logging_mutex );

		printf( ANSI_ESC_RED "Error: " ANSI_ESC_RESET );
		vprintf( msg, va_args );
		printf( "\n" );
	}

	va_end( va_args );
	fflush( stdout );

	std::terminate();
}


[[noreturn]]
void log_span_fatal( Span span, char const* msg, ... )
{
	va_list va_args;
	va_start( va_args, msg );

	FileData file_data = FileManager_GetFileData( span.file_id );
	const char* raw_file_data = file_data.raw_data;

	int64_t line_start = span.start - 1;

	while ( line_start >= 0 && raw_file_data[line_start] != '\n' ) line_start--;
	line_start++;


	{
		std::scoped_lock<std::mutex> lock( s_logging_mutex );

		printf( ANSI_ESC_RED "Error: " ANSI_ESC_RESET );
		vprintf( msg, va_args );
		printf( "\n" );

		printf( "%s:\n", file_data.name );

		printf( "\n%4zu| ", span.line );

		const char* read_head = raw_file_data + line_start;
		while ( *read_head != '\n' )
		{
			printf( "%c", *read_head );
			read_head++;
		}

		printf( "\n      " );

		for ( size_t i = line_start; i < span.start; i++ )
		{
			if ( raw_file_data[i] == '\t' )
				printf( "\t" );
			else
				printf( " " );
		}

		for ( size_t i = span.start; i < span.end; i++ )
		{
			printf( "^" );
		}

		printf( "\n\n" );
	}

	va_end( va_args );

	fflush( stdout );

	std::terminate();
}
