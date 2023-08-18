package main

import "core:fmt"
import "core:strings"


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
