#pragma once

#include "token.hh"

void log_info( char const* msg, ... );
void log_warn( char const* msg, ... );
void log_error( char const* msg, ... );
void log_span_fatal( Span span, char const* msg, ... );
