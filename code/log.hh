#pragma once

#include "token.hh"

void log_info( char const* msg, ... );
void log_warn( char const* msg, ... );
void log_error( char const* msg, ... );
[[noreturn]] void log_fatal( char const* msg, ... );
[[noreturn]] void log_span_fatal( Span span, char const* msg, ... );

#define span_assert( condition, span, ... ) \
	if ( !( condition ) ) \
	{ \
		log_span_fatal( span, __VA_ARGS__ ); \
	}
