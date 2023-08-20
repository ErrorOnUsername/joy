package main

import "core:fmt"
import "core:os"


main :: proc()
{
    compiler_init()
    defer compiler_deinit()

    id, ok := fm_open( "test/basic" )
    if !ok {
        fmt.eprintln( "Could not load file" )
        return
    }

    compiler_enqueue_work( .ParsePackage, id )

    tasks_failed := compiler_finish_work()
    if tasks_failed != 0 {
        fmt.printf( "Parsing phase failed! ({} task(s) reported errors)\n", tasks_failed )
        fmt.println( "Compilation failed" )
        return
    }

    fmt.println( "Compilation successful" )
}
