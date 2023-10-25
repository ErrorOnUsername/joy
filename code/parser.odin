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

	parse_ok := tokenize_file( data )
	parse_ok  = parse_ok && parse_top_level_stmnts( data, mod_ptr )

	return .Continue if parse_ok else .Error
}

parse_top_level_stmnts :: proc( file_data: ^FileData, mod: ^Module ) -> ( ok := true )
{
	first_tk := next_non_newline_tk( file_data )

	for ok && first_tk.kind != .EndOfFile {
		#partial switch first_tk.kind {
			case .Decl:
				decl_ptr := parse_decl( file_data )

				ok = decl_ptr != nil

				if ok {
					// TODO: Grab mutex
					append( &mod.owning_pkg.shared_scope.stmnts, decl_ptr )
				}
			case .Let:
				log_error( "impl globals" )
				ok = false
			case:
				log_errorf( "Unexpected token kind: {}", first_tk.kind )
				ok = false
		}

		first_tk = next_non_newline_tk( file_data )
	}

	return
}

parse_decl :: proc( file_data: ^FileData ) -> ^Stmnt
{
	name_tk := next_tk( file_data )

	if name_tk.kind != .Ident {
		log_spanned_error( &name_tk.span, "Expected identifier for declaration name, but got something else" )
	}

	colon_tk := next_tk( file_data )

	if colon_tk.kind == .Colon {
		distiction_tk := next_tk( file_data )

		#partial switch distiction_tk.kind {
			case .Struct: return parse_struct_decl( file_data, name_tk )
			case .Enum:   return parse_enum_decl( file_data, name_tk )
			case .Union:  return parse_union_decl( file_data, name_tk )
			case .LParen: return parse_proc_decl( file_data, name_tk )
		}
	}

	// If we made it here it was supposed to be a constant declaration

	log_error( "impl constants" )
	return nil
}

parse_struct_decl :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^StructDecl
{
	l_curly_tk := next_non_newline_tk( file_data )
	if l_curly_tk.kind != .LCurly {
		log_spanned_error( &l_curly_tk.span, "Expected '{' to begin struct body" );
	}

	decl := new_node( StructDecl, name_tk.span )
	decl.name = name_tk.str

	member, members_ok := parse_var_decl( file_data )

	for members_ok && member != nil {
		append( &decl.members, member )

		semicolon_tk := next_tk( file_data )
		if semicolon_tk.kind == .RCurly {
			file_data.tk_idx -= 1
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

	r_curly_tk := next_non_newline_tk( file_data )
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

parse_enum_decl :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^EnumDecl
{
	l_curly_tk := next_non_newline_tk( file_data )
	if l_curly_tk.kind != .LCurly {
		log_spanned_error( &l_curly_tk.span, "Expected '{' to begin enum body" )
		return nil
	}

	decl := new_node( EnumDecl, name_tk.span )
	decl.name = name_tk.str


	// TODO: Variant values
	variant_tk := next_non_newline_tk( file_data )

	for variant_tk.kind != .RCurly {
		if variant_tk.kind != .Ident {
			log_spanned_error( &variant_tk.span, "Expected identifier for enum variant name" )
			return nil
		}

		variant := new_node( EnumVariant, variant_tk.span )
		variant.name = variant_tk.str

		variant_tk = next_tk( file_data )
		if variant_tk.kind != .Semicolon {
			log_spanned_error( &variant_tk.span, "Expected ';' to terminate enum variant" )
			return nil
		}

		append( &decl.variants, variant )

		variant_tk = next_non_newline_tk( file_data )
	}

	return decl
}

parse_union_decl :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^UnionDecl
{
	log_error( "impl unions" )
	return nil
}

parse_proc_decl :: proc( file_data: ^FileData, name_tk: ^Token ) -> ^ProcDecl
{
	decl := new_node( ProcDecl, name_tk.span )
	decl.name    = name_tk.str
	decl.linkage = .Internal

	param, params_ok := parse_var_decl( file_data )
	found_r_paren := false

	for params_ok && param != nil {
		append( &decl.params, param )

		comma_tk := next_tk( file_data )

		if comma_tk.kind == .RParen {
			file_data.tk_idx -= 1
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

	r_paren_tk := next_tk( file_data )

	if r_paren_tk.kind != .RParen {
		log_spanned_error( &r_paren_tk.span, "Expected ')' to terminate parameter list" )
		return nil
	}

	ret_arrow := next_tk( file_data )
	if ret_arrow.kind == .SmolArrow {
		return nil
	} else {
		file_data.tk_idx -= 1
	}

	l_curly_tk := next_non_newline_tk( file_data )
	if l_curly_tk.kind != .LCurly {
		log_spanned_error( &l_curly_tk.span, "Expected '{' to start funtion body" )
		return nil
	}

	file_data.tk_idx -= 1

	decl.body = parse_scope( file_data )
	if decl.body == nil do return nil

	decl.body.parent = file_data.pkg.shared_scope

	return decl
}

parse_stmnt :: proc( file_data: ^FileData ) -> ^Stmnt
{
	start_tk := next_non_newline_tk( file_data )

	#partial switch start_tk.kind {
		case .Decl: return parse_decl( file_data )
		case .Let:
			var, ok := parse_var_decl( file_data )
			if !ok {
				span_ptr := &start_tk.span if var == nil else &var.span
				log_spanned_error( span_ptr, "Malformed var decl" )
				return nil
			}

			sc_tk := next_tk( file_data )
			if sc_tk.kind != .Semicolon {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after let statement" )
				return nil
			}

			return var
		case .LCurly:
			scope := parse_scope( file_data )

			block := new_node( BlockStmnt, start_tk.span )
			block.scope = scope

			return block
		case .If:    return parse_if_stmnt( file_data )
		case .For:   return parse_for_loop( file_data )
		case .While: return parse_while_loop( file_data )
		case .Loop:  return parse_loop_stmnt( file_data )
		case:
			file_data.tk_idx -= 1

			expr  := parse_expr( file_data )
			if expr == nil do return nil

			stmnt := new_node( ExprStmnt, expr.span )
			stmnt.expr = expr

			sc_tk := next_tk( file_data )
			if sc_tk.kind != .Semicolon {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after expression statement" )
				return nil
			}

			return stmnt
	}
}

parse_if_stmnt :: proc( file_data: ^FileData ) -> ^IfStmnt
{
	if_tk := &file_data.tokens[file_data.tk_idx - 1]
	if if_tk.kind != .If do return nil

	if_stmnt := new_node( IfStmnt, if_tk.span )

	cond_expr := parse_expr( file_data )
	if cond_expr == nil do return nil

	l_curly_tk := next_non_newline_tk( file_data )
	file_data.tk_idx -= 1
	if l_curly_tk.kind != .LCurly {
		log_spanned_error( &l_curly_tk.span, "Expected '{' after if condition" )
		return nil
	}

	then_block := parse_scope( file_data )
	if then_block == nil do return nil

	if_stmnt.span.end   = then_block.span.end
	if_stmnt.then_block = then_block


	maybe_else_tk := next_non_newline_tk( file_data )
	if maybe_else_tk.kind != .Else {
		file_data.tk_idx -= 1
		return if_stmnt
	}

	maybe_if_tk := next_non_newline_tk( file_data )
	file_data.tk_idx -= 1

	if maybe_if_tk.kind == .If {
		file_data.tk_idx += 1 // :'(

		else_stmnt := parse_if_stmnt( file_data )
		if else_stmnt == nil do return nil

		if_stmnt.else_stmnt = else_stmnt
	} else if maybe_if_tk.kind == .LCurly {

		else_scope := parse_scope( file_data )
		if else_scope == nil do return nil

		else_span, join_ok := join_span( &maybe_if_tk.span, &file_data.tokens[file_data.tk_idx].span )
		if !join_ok do return nil

		else_stmnt := new_node( IfStmnt, else_span )
		else_stmnt.then_block = else_scope

		if_stmnt.else_stmnt = else_stmnt
	}

	return if_stmnt
}

parse_for_loop :: proc( file_data: ^FileData ) -> ^Stmnt
{
	log_error( "impl parse_for_loop" )
	return nil
}

parse_while_loop :: proc( file_data: ^FileData ) -> ^Stmnt
{
	log_error( "impl parse_while_loop" )
	return nil
}

parse_loop_stmnt :: proc( file_data: ^FileData ) -> ^Stmnt
{
	log_error( "impl parse_loop_stmnt" )
	return nil
}

parse_scope :: proc( file_data: ^FileData ) -> ^Scope
{
	tk := next_non_newline_tk( file_data )
	if tk.kind != .LCurly do return nil

	scope := new_node( Scope, tk.span )

	tk = next_non_newline_tk( file_data )
	for tk.kind != .RCurly {
		file_data.tk_idx -= 1 // yikes...

		stmnt := parse_stmnt( file_data )
		if stmnt == nil do return nil

		block, ok := stmnt.derived_stmnt.(^BlockStmnt)
		if ok {
			block.scope.parent = scope
		}

		append( &scope.stmnts, stmnt )

		tk = next_non_newline_tk( file_data )
	}

	return scope
}

parse_var_decl :: proc( file_data: ^FileData ) -> ( ^VarDecl, bool )
{
	name_tk := next_non_newline_tk( file_data )

	if name_tk.kind != .Ident {
		file_data.tk_idx -= 1
		return nil, true
	}

	decl := new_node( VarDecl, name_tk.span )
	decl.name = name_tk.str


	colon_tk := next_tk( file_data )

	if colon_tk.kind == .Colon {
		decl.type = parse_type( file_data )

		if decl.type == nil do return nil, false
	} else if colon_tk.kind != .ColonAssign {
		log_spanned_errorf( &colon_tk.span, "Expected ':' or ':=' after identifier, but got '{}'", colon_tk.kind )
		return nil, false
	}

	assign_tk := next_tk( file_data )

	if decl.type == nil || ( decl.type != nil && assign_tk.kind == .Assign ) {
		if decl.type == nil {
			file_data.tk_idx -= 1
		}

		decl.default_value = parse_expr( file_data )
		if decl.default_value == nil do return nil, false
	} else {
		file_data.tk_idx -= 1
	}

	return decl, true
}

parse_type :: proc( file_data: ^FileData ) -> ^Type
{
	lead_tk := next_tk( file_data )

	#partial switch lead_tk.kind {
		case .U8, .I8, .U16, .I16, .U32, .I32, .U64, .I64, .USize, .ISize, .F32, .F64, .String, .CString, .RawPtr:
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

parse_expr :: proc( file_data: ^FileData, can_create_struct_literal := false ) -> ^Expr
{
	// 1. get the first operand (lhs)
	// 2. peek the operator
	//      - if none, return
	// 4. get the next operand (rhs)
	// 5. peek the next operator
	//      - if it's a higher priority, build that as the nested expr

	lhs := parse_operand( file_data, can_create_struct_literal )
	if lhs == nil do return nil

	op_tk := next_non_newline_tk( file_data )

	op := tk_to_bin_op( op_tk )

	for {
		if op == .Invalid {
			file_data.tk_idx -= 1
			break
		}

		rhs := parse_operand( file_data, false )
		if rhs == nil do return nil

		peek_op_tk := next_non_newline_tk( file_data )

		peek_op := tk_to_bin_op( peek_op_tk )

		if peek_op != .Invalid && bin_op_priority( peek_op ) > bin_op_priority( op ) {
			new_lhs := rhs
			new_rhs := parse_operand( file_data, false )
			if new_rhs == nil do return nil

			new_span, ok := join_span( &new_lhs.span, &new_rhs.span )
			if !ok do return nil

			rhs_bop := new_node( BinOpExpr, new_span )
			rhs_bop.op  = peek_op
			rhs_bop.lhs = new_lhs
			rhs_bop.rhs = new_rhs

			rhs = rhs_bop
		} else {
			file_data.tk_idx -= 1
		}

		span, ok := join_span( &lhs.span, &rhs.span )
		if !ok do return nil

		bop := new_node( BinOpExpr, span )
		bop.op = op
		bop.lhs = lhs
		bop.rhs = rhs

		lhs = bop

		op_tk = next_non_newline_tk( file_data )
		op    = tk_to_bin_op( op_tk )
	}

	return lhs
}

parse_operand :: proc( file_data: ^FileData, can_create_struct_literal: bool ) -> ^Expr
{
	lead_tk := next_non_newline_tk( file_data )

	#partial switch lead_tk.kind {
		case .Dot:
			log_spanned_error( &lead_tk.span, "impl auto type '.' prefix" )
			return nil
		case .PlusPlus:
			log_spanned_error( &lead_tk.span, "impl prefix increment" )
			return nil
		case .MinusMinus:
			log_spanned_error( &lead_tk.span, "impl prefix decrement" )
			return nil
		case .Star:
			log_spanned_error( &lead_tk.span, "impl dereference" )
			return nil
		case .Minus:
			log_spanned_error( &lead_tk.span, "impl negate" )
			return nil
		case .Number:
			node := new_node( NumberLiteralExpr, lead_tk.span )
			node.str = lead_tk.str

			return node
		case .StringLiteral:
			node := new_node( StringLiteralExpr, lead_tk.span )
			node.str = lead_tk.str

			return node
	}

	if lead_tk.kind != .Ident {
		log_spanned_error( &lead_tk.span, "Unexpected token in operand" )
	}

	tail_tk := next_tk( file_data )

	#partial switch tail_tk.kind {
		case .LParen:
			call_expr := new_node( ProcCallExpr, tail_tk.span )
			call_expr.name = lead_tk.str

			params_ok := parse_proc_call_param_pack( file_data, call_expr )
			if !params_ok do return nil

			return call_expr
		case .LCurly:
			if can_create_struct_literal {
				log_spanned_error( &tail_tk.span, "impl struct literals" )
				return nil
			}
	}

	file_data.tk_idx -= 1

	ident := new_node( Ident, lead_tk.span )
	ident.name = lead_tk.str

	return ident
}

parse_proc_call_param_pack :: proc( file_data: ^FileData, call_expr: ^ProcCallExpr ) -> ( ok := true )
{
	tk := next_tk( file_data )

	if tk.kind != .RParen {
		file_data.tk_idx -= 1
	}

	for tk.kind != .RParen {
		expr := parse_expr( file_data, true )
		if expr == nil {
			ok = false
			break
		}

		append( &call_expr.params, expr )

		tk = next_tk( file_data )

		if tk.kind != .RParen && tk.kind != .Comma {
			log_spanned_error( &tk.span, "Expected ',' or ')' after procedure call parameter" )
			ok = false
			break
		}
	}

	return
}

next_tk :: proc( file_data: ^FileData ) -> ^Token
{
	tk := &file_data.tokens[file_data.tk_idx]
	file_data.tk_idx += 1

	return tk
}

next_non_newline_tk :: proc( file_data: ^FileData ) -> ^Token
{
	tk := next_tk( file_data )

	for tk.kind == .EndOfLine {
		tk = next_tk( file_data )
	}

	return tk
}

