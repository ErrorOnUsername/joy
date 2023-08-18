package main

import "core:fmt"
import "core:os"


main :: proc()
{
    defer fm_shutdown()
    id, ok := fm_open( "test/basic/main.dfly" )
    if !ok {
        fmt.eprintln( "Could not load file" )
        return
    }


    result := compiler_pump( .ParseFile, id )
    if result == .Error
    {
        fmt.eprintln( "Compilation failed" )
        return
    }

    fmt.println( "Compilation successful" )
}
