package main

import "core:os"
import "core:path/filepath"


FileID :: uint

FileData :: struct
{
    id:       FileID,
    abs_path: string,
    rel_path: string,
    is_dir:   bool,
    data:     string,
    read_idx: uint,

    pkg: ^Package,
}

file_id_map:   map[string]FileID
file_registry: [dynamic]FileData


fm_open :: proc( path: string ) -> ( id: FileID, ok: bool )
{
    working_dir := os.get_current_directory()
    defer delete( working_dir )

    abs_path, abs_path_ok := filepath.abs( path )
    if !abs_path_ok {
        log_errorf( "Could not get absolute path for given path: '{}'", path )
        ok = false
        return
    }

    rel_path, lex_err := filepath.rel( working_dir, abs_path )
    if lex_err != .None {
        log_errorf( "Failed to create relative path from absolute path '{}' with error: {}", abs_path, lex_err );
        ok = false
        return
    }


    if abs_path in file_id_map {
        log_warningf( "Tried to open file '{}', but it's already been opened", rel_path )

        id = file_id_map[abs_path]
        ok = true

        return
    }

    is_dir := os.is_dir( abs_path )

    raw_data: []u8
    read_ok: bool

    if !is_dir {
        raw_data, read_ok = os.read_entire_file( path )
        if !read_ok {
            id = 0
            ok = false

            return
        }
    }

    new_data: FileData
    new_data.id       = len( file_registry )
    new_data.abs_path = abs_path
    new_data.rel_path = rel_path
    new_data.is_dir   = is_dir
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
