package main

import "core:fmt"
import "core:mem"
import "core:strings"


pump_parse_file :: proc( owning_package: ^Package, file_id: FileID ) -> PumpResult
{
    data := fm_get_data( file_id )
    if data == nil {
        log_errorf( "Could not get file data of id {}", file_id )
        return .Error
    }

    fmt.println( data.data )

    token: Token
    token.kind = .Invalid

    for token.kind != .EndOfFile {
        get_ok := next_token( data, &token )
        if !get_ok {
            log_errorf( "Got invalid token at span {}", token.span )
            return .Error
        }

        fmt.printf( "Got token '{}'\n", token )
    }

    return .Continue
}

next_token :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
    token^ = { }

    if data.read_idx >= len( data.data ) {
        end := len( data.data )

        token.kind = .EndOfFile
        token.span = { uint( end - 1 ), uint( end ) }
        return
    }

    for data.data[data.read_idx] == ' ' {
        data.read_idx += 1
    }

    start_ch := data.data[data.read_idx]
    switch start_ch {
        case ':':
            data.read_idx += 1

            token.kind = .Colon
            token.span = { data.read_idx - 1 , data.read_idx }
        case ';':
            data.read_idx += 1

            token.kind = .Semicolon
            token.span = { data.read_idx - 1 , data.read_idx }
        case '(':
            data.read_idx += 1

            token.kind = .LParen
            token.span = { data.read_idx - 1 , data.read_idx }
        case ')':
            data.read_idx += 1

            token.kind = .RParen
            token.span = { data.read_idx - 1 , data.read_idx }
        case '{':
            data.read_idx += 1

            token.kind = .LCurly
            token.span = { data.read_idx - 1 , data.read_idx }
        case '}':
            data.read_idx += 1

            token.kind = .RCurly
            token.span = { data.read_idx - 1 , data.read_idx }
        case '\r':
            if data.data[data.read_idx + 1] != '\n' {
                log_errorf( "Carriage return not followed by newline??? Got {:q} instead", rune( data.data[data.read_idx + 1] ) )
                token.kind = .Invalid
                ok = false
            } else {
                token.kind = .EndOfLine
            }

            token.span = { data.read_idx, data.read_idx + 2 }
            data.read_idx += 2
        case '\n':
            data.read_idx += 1

            token.kind = .EndOfLine
            token.span = { data.read_idx - 1, data.read_idx }
        case '"':
            ok = get_string_literal( data, token )
        case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
            token.span = { data.read_idx, data.read_idx + 1 }
            log_error( "implement number literal parsing" )
            ok = false
        case:
            ok = get_ident_or_keword( data, token )
    }

    return
}

get_string_literal :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
    data.read_idx += 1

    sb := strings.builder_make()
    defer strings.builder_destroy( &sb )

    data_size       := uint( len( data.data ) )
    start           := data.read_idx
    found_end_quote := false

    for !found_end_quote && data.read_idx < data_size {
        c := data.data[data.read_idx]
        if c == '\\' {
            esc_c := data.data[data.read_idx + 1]

            switch esc_c {
                case 'r':
                    strings.write_byte( &sb, '\r' )
                case 'n':
                    strings.write_byte( &sb, '\n' )
                case 'e':
                    strings.write_byte( &sb, '\x1b' )
                case 't':
                    strings.write_byte( &sb, '\t' )
                case 'x':
                    log_error( "implement hexadecimal string escapes (i.e. '\\x1b')" )
                    ok = false
                    return
                case:
                    strings.write_byte( &sb, esc_c )
            }

            data.read_idx += 2
            continue
        }

        if c == '"' {
            found_end_quote = true
        } else {
            strings.write_byte( &sb, c )
        }

        data.read_idx += 1
    }

    token.span = { start, data.read_idx - 1 }

    if !found_end_quote {
        log_error( "Unterminated string literal" )
        ok = false
    } else {
        token.kind = .String
        token.str  = strings.to_string( sb )
    }

    return
}

keyword_map := map[string]TokenKind {
    "decl" = .Decl,
    "let"  = .Let,
}

get_ident_or_keword :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
    start := data.read_idx
    for is_valid_ident_char( data.data[data.read_idx] )
    {
        data.read_idx += 1
    }

    ident_slice := data.data[start:data.read_idx]

    token.span = { start, data.read_idx }

    if ident_slice in keyword_map {
        token.kind = keyword_map[ident_slice]
    } else {
        token.kind = .Ident
        token.str  = ident_slice
    }

    return
}

is_valid_ident_char :: proc( c: u8 ) -> bool
{
    return ( c >= 'a' && c <= 'z' ) || ( c >= 'A' && c <= 'Z' ) || ( c >= '0' && c <= '9' ) || c == '_'
}


Span :: struct
{
    start: uint,
    end:   uint,
}

Token :: struct
{
    kind: TokenKind,
    span: Span,
    str:  string,
}

TokenKind :: enum
{
    Invalid,

    EndOfLine,
    EndOfFile,

    Decl,
    Let,

    Ident,
    String,

    Colon,
    Semicolon,

    LParen,
    RParen,
    LCurly,
    RCurly,
}
