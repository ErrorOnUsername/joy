package main

import "core:fmt"
import "core:os"

CompilerMode :: enum
{
    None,
    Build,
    BuildAndRun,
    Help,
}

CLState :: struct
{
    mode: CompilerMode,
}

g_cl_state: CLState
g_usage_string := `Usage:
    {} <mode>

modes:
    build

    run

    help
`

print_usage :: proc()
{
    fmt.printf( g_usage_string, os.args[0] )
}

parse_args :: proc() -> bool
{
    if len( os.args ) < 2 {
        print_usage()
        return false
    }

    mode := os.args[1]
    g_cl_state.mode = .None

    switch mode {
        case "build":
            g_cl_state.mode = .Build

        case "run":
            g_cl_state.mode = .BuildAndRun

        case "help":
            g_cl_state.mode = .Help

            print_usage()
            return true
    }

    if g_cl_state.mode == .None {
        fmt.printf( "invalid compiler mode: '{}'\n", mode )
        print_usage()
        return false
    }

    return true
}
