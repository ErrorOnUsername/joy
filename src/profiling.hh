#pragma once

#define USE_OPTICK 1
#include "optick.h"

#define TIME_MAIN()        OPTICK_FRAME( "Main Thread" )
#define TIME_PROC()        OPTICK_EVENT()
#define TIME_SCOPE( name ) OPTICK_EVENT( name )

#define PROF_APP( name )          OPTICK_APP( name )
#define PROF_START_THREAD( name ) OPTICK_START_THREAD( name )
#define PROF_END_THREAD()         OPTICK_END_THREAD()

#define TIME_THREAD( name ) OPTICK_THREAD( name )

