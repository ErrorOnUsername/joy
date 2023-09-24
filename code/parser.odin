package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"


pump_parse_package :: proc( file_id: FileID ) -> PumpResult
{
    file_data := fm_get_data( file_id )

    if !file_data.is_dir {
        log_errorf( "Package '{}' is not a directory", file_data.rel_path )
        return .Error
    }

    if file_data.pkg != nil {
        log_errorf( "Tried to parse a package '{}' that's already been parsed (cyclical reference?)", file_data.rel_path )
        return .Error
    }

    pkg, _ := new( Package )
    pkg.shared_scope = new_node( Scope, { file_id, 0, 0 } )

    file_data.pkg = pkg

    handle, open_errno := os.open( file_data.abs_path )
    defer os.close( handle )

    if open_errno != os.ERROR_NONE {
        log_errorf( "Could not open directory: '{}' (errno: {})", file_data.rel_path, open_errno )
        return .Error
    }


    f_infos, errno := os.read_dir( handle, -1 )

    for f_info in f_infos {
        sub_file_id, open_ok := fm_open( f_info.fullpath )
        sub_file_data        := fm_get_data( sub_file_id )

        sub_file_data.pkg = file_data.pkg

        compiler_enqueue_work( .ParsePackage if sub_file_data.is_dir else .ParseFile, sub_file_id )
    }

    return .Continue
}

pump_parse_file :: proc( file_id: FileID ) -> PumpResult
{
    data := fm_get_data( file_id )
    if data == nil {
        log_errorf( "Could not get file data of id {}", file_id )
        return .Error
    }

    fmt.println( data.data )

    mod_ptr, _ := mem.new( Module, tl_ast_allocator )
    mod_ptr.owning_pkg    = data.pkg
    mod_ptr.private_scope = new_node( Scope, { file_id, 0, 0 } )

    append( &mod_ptr.owning_pkg.modules, mod_ptr )

    token: Token
    token.kind = .Invalid

    parse_ok := parse_top_level_stmnts( data, mod_ptr )

    return .Continue if parse_ok else .Error
}

parse_top_level_stmnts :: proc( file_data: ^FileData, mod: ^Module ) -> ( ok := true )
{
    first_tk: Token
    next_non_newline_tk( file_data, &first_tk )

    for ok && first_tk.kind != .EndOfFile {
        #partial switch first_tk.kind {
            case .Decl:
                decl_ptr := parse_decl( file_data )

                ok = decl_ptr != nil
            case .Let:
                log_error( "impl globals" )
                ok = false
            case:
                log_errorf( "Unexpected token kind: {}", first_tk.kind )
                ok = false
        }

        next_non_newline_tk( file_data, &first_tk )
    }

    return
}

parse_decl :: proc( file_data: ^FileData ) -> ^Stmnt
{
    name_tk: Token
    next_token( file_data, &name_tk )

    if name_tk.kind != .Ident {
        log_spanned_error( &name_tk.span, "Expected identifier for declaration name, but got something else" )
    }

    colon_tk: Token
    next_token( file_data, &colon_tk )

    if colon_tk.kind == .Colon {
        distiction_tk: Token
        next_token( file_data, &distiction_tk )

        file_data.read_idx = name_tk.span.start

        #partial switch distiction_tk.kind {
            case .Struct: return parse_struct_decl( file_data )
            case .Enum:   return parse_enum_decl( file_data )
            case .Union:  return parse_union_decl( file_data )
            case .LParen: return parse_proc_decl( file_data )
        }
    } else {
        file_data.read_idx = name_tk.span.start
    }

    // If we made it here it was supposed to be a constant declaration

    log_error( "impl constants" )
    return nil
}

parse_struct_decl :: proc( file_data: ^FileData ) -> ^StructDecl
{
    name_tk: Token
    next_token( file_data, &name_tk )
    if name_tk.kind != .Ident do return nil

    colon_tk: Token
    next_token( file_data, &colon_tk )
    if colon_tk.kind != .Colon do return nil

    struct_tk: Token
    next_token( file_data, &struct_tk )
    if struct_tk.kind != .Struct do return nil

    l_curly_tk: Token
    next_non_newline_tk( file_data, &l_curly_tk )
    if l_curly_tk.kind != .LCurly {
        log_spanned_error( &l_curly_tk.span, "Expected '{' to begin struct body" );
    }

    decl := new_node( StructDecl, name_tk.span )
    decl.name = name_tk.str

    member, members_ok := parse_var_decl( file_data )

    for members_ok && member != nil {
        append( &decl.members, member )

        semicolon_tk: Token
        next_token( file_data, &semicolon_tk )
        if semicolon_tk.kind == .RCurly {
            file_data.read_idx = semicolon_tk.span.start
            break
        } else if semicolon_tk.kind != .Semicolon {
            log_spanned_error( &semicolon_tk.span, "Expected ';' to terminate structure member" )
            return nil
        }

        member, members_ok = parse_var_decl( file_data )
    }

    if !members_ok {
        log_spanned_error( &decl.span, "Failed to parse struct members" )
        return nil
    }

    r_curly_tk: Token
    next_non_newline_tk( file_data, &r_curly_tk )
    if r_curly_tk.kind != .RCurly {
        log_spanned_error( &r_curly_tk.span, "Expected '}' to terminate struct declaration" )
        return nil
    }

    if len( decl.members ) == 0 {
        log_spanned_error( &decl.span, "Struct declaration is empty" )
        return nil
    }

    return decl
}

parse_enum_decl :: proc( file_data: ^FileData ) -> ^EnumDecl
{
    name_tk: Token
    next_token( file_data, &name_tk )
    if name_tk.kind != .Ident do return nil

    colon_tk: Token
    next_token( file_data, &colon_tk )
    if colon_tk.kind != .Colon do return nil

    enum_tk: Token
    next_token( file_data, &enum_tk )
    if enum_tk.kind != .Enum do return nil

    l_curly_tk: Token
    next_non_newline_tk( file_data, &l_curly_tk )
    if l_curly_tk.kind != .LCurly {
        log_spanned_error( &l_curly_tk.span, "Expected '{' to begin enum body" )
        return nil
    }

    decl := new_node( EnumDecl, name_tk.span )
    decl.name = name_tk.str


    // TODO: Variant values
    variant_tk: Token
    next_non_newline_tk( file_data, &variant_tk )

    for variant_tk.kind != .RCurly {
        if variant_tk.kind != .Ident {
            log_spanned_error( &variant_tk.span, "Expected identifier for enum variant name" )
            return nil
        }

        variant := new_node( EnumVariant, variant_tk.span )
        variant.name = variant_tk.str

        next_token( file_data, &variant_tk )
        if variant_tk.kind != .Semicolon {
            log_spanned_error( &variant_tk.span, "Expected ';' to terminate enum variant" )
            return nil
        }

        append( &decl.variants, variant )

        next_non_newline_tk( file_data, &variant_tk )
    }

    return decl
}

parse_union_decl :: proc( file_data: ^FileData ) -> ^UnionDecl
{
    log_error( "impl unions" )
    return nil
}

parse_proc_decl :: proc( file_data: ^FileData ) -> ^ProcDecl
{
    name_tk: Token
    next_token( file_data, &name_tk )
    if name_tk.kind != .Ident do return nil

    colon_tk: Token
    next_token( file_data, &colon_tk )
    if colon_tk.kind != .Colon do return nil

    l_paren_tk: Token
    next_token( file_data, &l_paren_tk )
    if l_paren_tk.kind != .LParen do return nil

    decl := new_node( ProcDecl, name_tk.span )
    decl.name    = name_tk.str
    decl.linkage = .Internal

    param, params_ok := parse_var_decl( file_data )
    found_r_paren := false

    for params_ok && param != nil {
        append( &decl.params, param )

        comma_tk: Token
        next_token( file_data, &comma_tk )

        if comma_tk.kind == .RParen {
            file_data.read_idx = comma_tk.span.start
            break
        } else if comma_tk.kind != .Comma {
            log_spanned_error( &comma_tk.span, "Expected ',' to separate procedure parameters")
        }

        param, params_ok = parse_var_decl( file_data )
    }

    if !params_ok {
        log_spanned_error( &name_tk.span, "Malfomed parameter list for procedure decl" )
        return nil
    }

    r_paren_tk: Token
    next_token( file_data, &r_paren_tk )

    if r_paren_tk.kind != .RParen {
        log_spanned_error( &r_paren_tk.span, "Expected ')' to terminate parameter list" )
        return nil
    }

    ret_arrow: Token
    next_token( file_data, &ret_arrow )
    if ret_arrow.kind == .SmolArrow {
    } else {
        file_data.read_idx = ret_arrow.span.start
    }

    l_curly_tk: Token
    next_non_newline_tk( file_data, &l_curly_tk )
    if l_curly_tk.kind != .LCurly {
        log_spanned_error( &l_curly_tk.span, "Expected '{' to start funtion body" )
        return nil
    }

    file_data.read_idx = l_curly_tk.span.start

    decl.body = parse_scope( file_data )
    if decl.body == nil do return nil

    decl.body.parent = file_data.pkg.shared_scope

    return decl
}

parse_stmnt :: proc( file_data: ^FileData ) -> ^Stmnt
{
    start_tk: Token
    next_non_newline_tk( file_data, &start_tk )

    #partial switch start_tk.kind {
        case .Decl: return parse_decl( file_data )
        case .Let:
            var, ok := parse_var_decl( file_data )
            if !ok {
                span_ptr := &start_tk.span if var == nil else &var.span
                log_spanned_error( span_ptr, "Malformed var decl" )
            }

            return var
        case:
            expr  := parse_expr( file_data )
            stmnt := new_node( ExprStmnt, expr.span )
            stmnt.expr = expr

            return stmnt
    }
}

parse_scope :: proc( file_data: ^FileData ) -> ^Scope
{
    l_curly_tk: Token
    next_token( file_data, &l_curly_tk )
    if l_curly_tk.kind != .LCurly do return nil

    log_error( "impl parse_scope" )
    return nil
}

parse_var_decl :: proc( file_data: ^FileData ) -> ( ^VarDecl, bool )
{
    name_tk: Token
    next_non_newline_tk( file_data, &name_tk )

    if name_tk.kind != .Ident {
        file_data.read_idx = name_tk.span.start
        return nil, true
    }

    decl := new_node( VarDecl, name_tk.span )
    decl.name = name_tk.str


    colon_tk: Token
    next_token( file_data, &colon_tk )

    if colon_tk.kind == .Colon {
        decl.type = parse_type( file_data )

        if decl.type == nil do return nil, false
    } else if colon_tk.kind != .ColonAssign {
        log_spanned_errorf( &colon_tk.span, "Expected ':' or ':=' after identifier, but got '{}'", colon_tk.kind )
        return nil, false
    }

    assign_tk: Token
    next_token( file_data, &assign_tk )

    if decl.type == nil || ( decl.type != nil && assign_tk.kind == .Assign ) {
        decl.default_value = parse_expr( file_data )
    } else {
        file_data.read_idx = assign_tk.span.start
    }

    return decl, true
}

parse_type :: proc( file_data: ^FileData ) -> ^Type
{
    lead_tk: Token
    next_token( file_data, &lead_tk )

    #partial switch lead_tk.kind {
        case .U8, .I8, .U16, .I16, .U32, .I32, .U64, .I64, .F32, .F64:
            prim := new_type( PrimitiveType )
            prim.kind = type_prim_kind_from_tk( lead_tk.kind )

            return prim
        case .Star:
            log_error( "impl pointer parsing" )
            return nil
        case .LSquare:
            log_error( "impl array/slice parsing" )
            return nil
        case .Ident:
            log_error( "impl type name parsing" )
            return nil
    }

    return nil
}

parse_expr :: proc( file_data: ^FileData ) -> ^Expr
{
    log_error( "impl expr parsing" )
    return nil
}

next_non_newline_tk :: proc( file_data: ^FileData, tk: ^Token )
{
    next_token( file_data, tk )

    for tk.kind == .EndOfLine {
        next_token( file_data, tk )
    }
}

next_token :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
    token^ = { }

    if data.read_idx >= len( data.data ) {
        end := len( data.data )

        token.kind = .EndOfFile
        token.span = { data.id, uint( end - 1 ), uint( end ) }
        return
    }

    for data.data[data.read_idx] == ' ' {
        data.read_idx += 1
    }

    full_data_len := uint( len( data.data ) )

    start_ch := data.data[data.read_idx]
    switch start_ch {
        case ':':
            data.read_idx += 1

            if data.read_idx < full_data_len && data.data[data.read_idx] == '=' {
                data.read_idx += 1

                token.kind = .ColonAssign
                token.span = { data.id, data.read_idx - 1 , data.read_idx }
            } else {
                token.kind = .Colon
                token.span = { data.id, data.read_idx - 1 , data.read_idx }
            }
        case ';':
            data.read_idx += 1

            token.kind = .Semicolon
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '(':
            data.read_idx += 1

            token.kind = .LParen
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case ')':
            data.read_idx += 1

            token.kind = .RParen
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '{':
            data.read_idx += 1

            token.kind = .LCurly
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '}':
            data.read_idx += 1

            token.kind = .RCurly
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '[':
            data.read_idx += 1

            token.kind = .LSquare
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case ']':
            data.read_idx += 1

            token.kind = .RSquare
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '*':
            data.read_idx += 1

            token.kind = .Star
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '=':
            data.read_idx += 1

            token.kind = .Assign
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case ',':
            data.read_idx += 1

            token.kind = .Comma
            token.span = { data.id, data.read_idx - 1 , data.read_idx }
        case '\r':
            if data.data[data.read_idx + 1] != '\n' {
                log_errorf( "Carriage return not followed by newline??? Got {:q} instead", rune( data.data[data.read_idx + 1] ) )
                token.kind = .Invalid
                ok = false
            } else {
                token.kind = .EndOfLine
            }

            token.span = { data.id, data.read_idx, data.read_idx + 2 }
            data.read_idx += 2
        case '\n':
            data.read_idx += 1

            token.kind = .EndOfLine
            token.span = { data.id, data.read_idx - 1, data.read_idx }
        case '"':
            ok = get_string_literal( data, token )
        case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
            token.span = { data.id, data.read_idx, data.read_idx + 1 }
            log_error( "implement number literal parsing" )
            ok = false
        case:
            ok = get_ident_or_keword( data, token )
    }

    if token.kind != .Invalid && len( token.str ) == 0 {
        token.str = data.data[token.span.start:token.span.end]
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

    token.span = { data.id, start, data.read_idx - 1 }

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
    "decl"   = .Decl,
    "let"    = .Let,
    "struct" = .Struct,
    "enum"   = .Enum,
    "union"  = .Union,
    "u8"     = .U8,
    "i8"     = .I8,
    "u16"    = .U16,
    "i16"    = .I16,
    "u32"    = .U32,
    "i32"    = .I32,
    "u64"    = .U64,
    "i64"    = .I64,
    "f32"    = .F32,
    "f64"    = .F64,
}

get_ident_or_keword :: proc( data: ^FileData, token: ^Token ) -> ( ok := true )
{
    start := data.read_idx
    for is_valid_ident_char( data.data[data.read_idx] )
    {
        data.read_idx += 1
    }

    ident_slice := data.data[start:data.read_idx]

    token.span = { data.id, start, data.read_idx }

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
    file:  FileID,
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

    Struct,
    Enum,
    Union,

    Ident,
    String,

    Assign,

    Star,
    Comma,
    Colon,
    ColonAssign,
    Semicolon,

    SmolArrow,

    LParen,
    RParen,
    LCurly,
    RCurly,
    LSquare,
    RSquare,

    U8,
    I8,
    U16,
    I16,
    U32,
    I32,
    U64,
    I64,
    F32,
    F64,
}
