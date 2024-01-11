package main

import "core:c/libc"
import "core:fmt"
import "core:strings"
import "core:sync"

log_mutex: sync.Mutex


log_spanned_error :: proc( span: ^Span, msg: string )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_error_internal( msg )
	print_span( span )

	libc.fflush( libc.stderr )
}

log_spanned_errorf :: proc( span: ^Span, msg: string, args: ..any )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_errorf_internal( msg, args )
	print_span( span )

	libc.fflush( libc.stderr )
}

log_error_internal :: proc( msg: string )
{
	fmt.eprintf( "Error: {}\n", msg )
}


log_error :: proc( msg: string )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_error_internal( msg )

	libc.fflush( libc.stderr )
}


log_errorf_internal :: proc( msg: string, args: ..any )
{
	sb: strings.Builder

	fmt.sbprintf( &sb, msg, args )
	fmt.eprintf( "Error: {}\n", strings.to_string( sb ) )
}


log_errorf :: proc( msg: string, args: ..any )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_errorf_internal( msg, args )

	libc.fflush( libc.stderr )
}


log_warning_internal :: proc( msg: string )
{
	fmt.eprintf( "Warning: {}\n", msg )
}


log_warning :: proc( msg: string )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_warning_internal( msg )
}


log_warningf_internal :: proc( msg: string, args: ..any )
{
	sb: strings.Builder

	fmt.sbprintf( &sb, msg, args )
	fmt.eprintf( "Warning: {}\n", strings.to_string( sb ) )
}


log_warningf :: proc( msg: string, args: ..any )
{
	sync.mutex_lock( &log_mutex )
	defer sync.mutex_unlock( &log_mutex )

	log_warningf_internal( msg, args )
}


print_span :: proc( span: ^Span )
{
	//
	// In the future, we should really just color the problematic span
	// red, rather than doing all this bs to draw arrows. That would
	// likely simplify this code quite a bit, but i'm just lazy rn, so
	// that's future me's problem :)
	//                         - rdavidson, 23 August, 2023 @ 23:09 PDT
	//

	if span.start >= span.end {
		fmt.printf( "Invalid span: {}\n", span^ )
		return
	}

	file_data := fm_get_data( span.file )

	fmt.printf( "{:s}:\n", file_data.rel_path )

	file_size  := len( file_data.data )
	idx        := 0
	line_start := 1
	line_end   := 1

	for idx < file_size && uint( idx ) < span.start {
		if file_data.data[idx] == '\n' {
			line_start += 1
			line_end   += 1
		}

		idx += 1
	}

	for idx < file_size && uint( idx ) < span.end {
		if uint( idx ) < span.end - 1 && file_data.data[idx] == '\n' {
			line_end += 1
		}

		idx += 1
	}

	if line_start != line_end {
		fmt.println( "TODO: multiline span {}", span^ )
	}

	line_col_start := span.start
	line_col_end   := span.end - 1

	for line_col_start > 0 {
		if file_data.data[line_col_start] == '\n' {
			line_col_start += 1
			break
		}

		line_col_start -= 1
	}

	for line_col_end < uint( file_size ) {
		if file_data.data[line_col_end] == '\n' || file_data.data[line_col_end] == '\r' {
			break
		}

		line_col_end += 1
	}

	line_slice := file_data.data[line_col_start:line_col_end]
	fmt.printf( "{: 4d}|{:s}\n", line_start, line_slice )
	fmt.printf( "     " )
	for i := line_col_start; i < span.end; i += 1 {
		if i >= span.start {
			fmt.printf( "^" )
		} else {
			fmt.printf( " " )
		}
	}
	fmt.printf( "\n" )
}
