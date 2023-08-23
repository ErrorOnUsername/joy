package main

import "core:fmt"
import "core:strings"

//
// FIXME: This need a mutex to protect it...
//


log_error :: proc( msg: string )
{
    fmt.eprintf( "Error: {}\n", msg )
}

log_errorf :: proc( msg: string, args: ..any )
{
    sb: strings.Builder

    fmt.sbprintf( &sb, msg, args )
    fmt.eprintf( "Error: {}\n", strings.to_string( sb ) )
}


log_warning :: proc( msg: string )
{
    fmt.eprintf( "Warning: {}\n", msg )
}

log_warningf :: proc( msg: string, args: ..any )
{
    sb: strings.Builder

    fmt.sbprintf( &sb, msg, args )
    fmt.eprintf( "Warning: {}\n", strings.to_string( sb ) )
}
