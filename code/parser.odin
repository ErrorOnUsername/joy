package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
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

	file_data.pkg = pkg

	handle, open_errno := os.open( file_data.abs_path )
	defer os.close( handle )

	if open_errno != os.ERROR_NONE {
		log_errorf( "Could not open directory: '{}' (errno: {})", file_data.rel_path, open_errno )
		return .Error
	}


	f_infos, errno := os.read_dir( handle, -1 )

	for f_info in f_infos {
		ext := filepath.ext( f_info.fullpath )
		if !f_info.is_dir && ext != ".joy" do continue

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
	mod_ptr.owning_pkg = data.pkg
	mod_ptr.file_scope = new_node( Scope, { file_id, 0, 0 } )
	mod_ptr.file_id    = file_id

	data.mod = mod_ptr

	append( &mod_ptr.owning_pkg.modules, mod_ptr )

	parse_ok := tokenize_file( data )
	parse_ok  = parse_ok && parse_top_level_stmnts( data, mod_ptr )

	return .Continue if parse_ok else .Error
}

parse_top_level_stmnts :: proc( file_data: ^FileData, mod: ^Module ) -> ( ok := true )
{
	first_tk := curr_tk( file_data )

	for ok && first_tk.kind != .EndOfFile {
		#partial switch first_tk.kind {
			case .Decl:
				decl_ptr := parse_decl( file_data, mod.file_scope )

				ok = decl_ptr != nil

				if ok {
					append( &mod.file_scope.stmnts, decl_ptr )
				}
			case .Let:
				log_error( "impl globals" )
				ok = false
			case .EndOfLine:
				file_data.tk_idx += 1
			case:
				log_errorf( "Unexpected token kind: {}", first_tk.kind )
				ok = false
		}

		first_tk = curr_tk( file_data )
	}

	return
}

parse_decl :: proc( file_data: ^FileData, scope: ^Scope ) -> ^ConstDecl
{
	if !try_consume_tk( file_data, .Decl ) {
		log_spanned_error( &curr_tk( file_data ).span, "expected 'decl" )
	}

	name_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .Ident ) {
		log_spanned_error( &name_tk.span, "Expected identifier for declaration name, but got something else" )
	}

	decl := new_node( ConstDecl, name_tk.span )

	if try_consume_tk( file_data, .Colon ) {
		decl.type_hint = parse_type( file_data )
		if decl.type_hint == nil do return nil
	} else if try_consume_tk( file_data, .ColonAssign ) {
		decl.value = parse_expr( file_data )
		if decl.value == nil do return nil
	}

	if decl.type_hint != nil {
		decl.value = parse_expr( file_data )
		if decl.value == nil do return nil
	}

	return decl
}

parse_struct_body :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^Scope
{
	struct_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .Struct ) {
		log_spanned_error( &struct_tk.span, "Expected 'struct' at beginning of struct body" )
		return nil
	}

	l_curly_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .LCurly ) {
		log_spanned_error( &l_curly_tk.span, "Expected '{' to begin struct body" )
		return nil
	}

	body := new_node( Scope, l_curly_tk.span )
	body.variant = .Struct

	member := parse_var_decl( file_data )

	for member != nil {
		append( &body.stmnts, member )

		semicolon_tk := curr_tk( file_data )
		if semicolon_tk.kind == .RCurly {
			break
		} else if !try_consume_tk( file_data, .Semicolon ) {
			log_spanned_error( &semicolon_tk.span, "Expected ';' to terminate structure member" )
			return nil
		}

		member = parse_var_decl( file_data )
	}

	if member == nil {
		return nil
	}

	r_curly_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .RCurly ) {
		log_spanned_error( &r_curly_tk.span, "Expected '}' to terminate struct declaration" )
		return nil
	}

	if len( body.stmnts ) == 0 {
		log_spanned_error( &body.span, "Struct declaration is empty" )
		return nil
	}

	return body
}

parse_enum_body :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^Scope
{
	enum_tk := curr_tk( file_data )
	log_spanned_error( &enum_tk.span, "impl 'enum' parsing" )
	return nil
}

parse_union_body :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^Scope
{
	union_tk := curr_tk( file_data )
	log_spanned_error( &union_tk.span, "impl 'union' parsing" )
	return nil
}

parse_proc_body :: proc( file_data: ^FileData, name_tk: ^Token, scope: ^Scope ) -> ^Scope
{
	proc_tk := curr_tk( file_data )
	log_spanned_error( &proc_tk.span, "impl 'proc' parsing" )
	return nil
}

parse_stmnt :: proc( file_data: ^FileData, scope: ^Scope ) -> ^Stmnt
{
	start_tk := curr_tk( file_data )

	#partial switch start_tk.kind {
		case .Decl: return parse_decl( file_data, scope )
		case .Let:
			var := parse_var_decl( file_data )
			if var == nil {
				return nil
			}

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after let statement" )
				return nil
			}

			return var
		case .Continue:
			continue_stmnt := new_node( ContinueStmnt, start_tk.span )

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after continue statement" )
				return nil
			}

			return continue_stmnt
		case .Break:
			break_stmnt := new_node( BreakStmnt, start_tk.span )

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after break statement" )
				return nil
			}

			return break_stmnt
		case .Return:
			log_spanned_error( &start_tk.span, "impl 'return' parsing" )
			return nil
		case:
			file_data.tk_idx -= 1

			expr  := parse_expr( file_data )
			if expr == nil do return nil

			stmnt := new_node( ExprStmnt, expr.span )
			stmnt.expr = expr

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after expression statement" )
				return nil
			}

			return stmnt
	}
}

parse_if_stmnt :: proc( file_data: ^FileData, scope: ^Scope ) -> ^IfExpr
{
	if_tk := curr_tk( file_data )
	log_spanned_error( &if_tk.span, "impl 'if' parsing" )
	return nil
}

parse_for_loop :: proc( file_data: ^FileData, scope: ^Scope ) -> ^ForLoop
{
	for_tk := curr_tk( file_data )
	log_spanned_error( &for_tk.span, "impl 'for' parsing" )
	return nil
}

parse_while_loop :: proc( file_data: ^FileData, scope: ^Scope ) -> ^WhileLoop
{
	while_tk := curr_tk( file_data )
	log_spanned_error( &while_tk.span, "impl 'while' parsing" )
	return nil
}

parse_loop_stmnt :: proc( file_data: ^FileData, scope: ^Scope ) -> ^InfiniteLoop
{
	loop_tk := curr_tk( file_data )
	log_spanned_error( &loop_tk.span, "impl 'loop' parsing" )
	return nil
}

parse_scope :: proc( file_data: ^FileData, parent_scope: ^Scope ) -> ^Scope
{
	l_curly_tk := curr_tk( file_data )
	log_spanned_error( &l_curly_tk.span, "impl logic scope parsing" )
	return nil
}

is_ident_tk :: proc( tk: TokenKind ) -> bool
{
	#partial switch tk {
		case .Bool, .U8, .I8, .U16, .I16, .U32,
		     .I32, .U64, .I64, .USize, .ISize,
		     .F32, .F64, .String, .CString,
		     .RawPtr, .Range, .Ident:
			return true
	}

	return false
}

parse_var_decl :: proc( file_data: ^FileData ) -> ^VarDecl
{
	start_tk := curr_tk( file_data )
	log_spanned_error( &start_tk.span, "impl var parsing" )
	return nil
}


parse_type :: proc( file_data: ^FileData ) -> ^Expr
{
	return parse_expr( file_data, false, true )
}


parse_expr :: proc( file_data: ^FileData, can_create_struct_literal := false, is_type := false ) -> ^Expr
{
	start_tk := curr_tk( file_data )
	log_spanned_error( &start_tk.span, "impl expr parsing" )
	return nil
}

parse_operand :: proc( file_data: ^FileData, can_create_struct_literal: bool ) -> ^Expr
{
	start_tk := curr_tk( file_data )
	log_spanned_error( &start_tk.span, "impl operand parsing" )
	return nil
}

curr_tk :: proc( data: ^FileData ) -> ^Token
{
	return &data.tokens[data.tk_idx]
}

try_consume_tk :: proc( data: ^FileData, kind: TokenKind ) -> bool
{
	if data.tokens[data.tk_idx].kind == kind {
		data.tk_idx += 1
		return true
	}

	return false
}

