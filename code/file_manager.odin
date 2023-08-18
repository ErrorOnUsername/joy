package main

import "core:os"


FileID :: uint

FileData :: struct
{
    id:       FileID,
    data:     string,
    read_idx: uint,
}

file_registry: [dynamic]FileData

fm_shutdown :: proc()
{
    for file_data in &file_registry
    {
        delete( file_data.data )
    }
}


fm_open :: proc( path: string ) -> ( id: FileID, ok: bool )
{
    raw_data, read_ok := os.read_entire_file( path )
    if !read_ok {
        id = 0
        ok = false

        return
    }
    defer delete( raw_data )

    new_data: FileData
    new_data.id       = len( file_registry )
    new_data.data     = string( raw_data )
    new_data.read_idx = 0

    append( &file_registry, new_data )

    id = len( file_registry ) - 1
    ok = true
    return
}


fm_get_data :: proc( id: FileID ) -> ^FileData
{
    if id > len( file_registry )
    {
        return nil
    }

    return &file_registry[id]
}
