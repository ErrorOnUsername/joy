#pragma once

#define USE_OPTICK 1
#include <optick.h>


#define PROF_START_APP( name )     OPTICK_APP( name )
#define TIME_MAIN()                OPTICK_FRAME( "Main Thread" )
#define TIME_PROC()                OPTICK_EVENT()
#define TIME_SCOPE( scope_name )   OPTICK_EVENT( scope_name )
#define TIME_THREAD( thread_name ) OPTICK_THREAD( thread_name )
