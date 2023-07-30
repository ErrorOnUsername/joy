#pragma once


#ifdef __linux__

#define USE_OPTICK 0
#include <optick.h>


#define PROF_START_APP( name )     OPTICK_APP( name )
#define TIME_MAIN()                OPTICK_FRAME( "Main Thread" )
#define TIME_PROC()                OPTICK_EVENT()
#define TIME_SCOPE( scope_name )   OPTICK_EVENT( scope_name )
#define TIME_THREAD( thread_name ) OPTICK_THREAD( thread_name )

#else

#define PROF_START_APP( name )
#define TIME_MAIN()
#define TIME_PROC()
#define TIME_SCOPE( scope_name )
#define TIME_THREAD( thread_name )

#endif

