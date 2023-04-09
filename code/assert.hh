#pragma once

#include "log.hh"

#ifdef WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <debugapi.h>

#define DF_ASSERT( condition, ... )                     \
	if ( !( condition ) )                               \
	{                                                   \
		log_error( "Assert failed: '%s'", #condition ); \
		log_info( "[%s : %d]:", __FILE__, __LINE__ );   \
		log_info( __VA_ARGS__ );                        \
		if ( IsDebuggerPresent() )                      \
		{                                               \
			__debugbreak();                             \
		}                                               \
		else                                            \
		{                                               \
			exit( 1 );                                  \
		}                                               \
	}

#else

#define DF_ASSERT( condition, ... )                     \
	if ( !( condition ) )                               \
	{                                                   \
		log_error( "Assert failed: '%s'", #condition ); \
		log_info( "[%s : %d]:", __FILE__, __LINE__ );   \
		log_info( __VA_ARGS__ );                        \
		exit( 1 );                                      \
	}

#endif
