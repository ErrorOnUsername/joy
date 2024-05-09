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
	mod_ptr.file_scope = new_node( Scope, { file_id, 0, 1 } )
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
			case .Use:
				log_spanned_error( &first_tk.span, "impl use statements" )
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
	decl.name = name_tk.str

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

	sc_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .Semicolon ) {
		log_spanned_error( &sc_tk.span, "Expected ';' to terminate decl statement" )
		return nil
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

parse_stmnt :: proc( file_data: ^FileData, scope: ^Scope ) -> ^Stmnt
{
	start_tk := curr_tk( file_data )

	#partial switch start_tk.kind {
		case .Decl: return parse_decl( file_data, scope )
		case .Let:
			if !try_consume_tk( file_data, .Let ) {
				log_spanned_error( &start_tk.span, "Expected 'let' at start of variable declaration" )
				return nil
			}

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
			if !try_consume_tk( file_data, .Continue ) {
				log_spanned_error( &start_tk.span, "Expected 'continue' at start of continue statement" )
				return nil
			}

			continue_stmnt := new_node( ContinueStmnt, start_tk.span )

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after continue statement" )
				return nil
			}

			return continue_stmnt
		case .Break:
			if !try_consume_tk( file_data, .Break ) {
				log_spanned_error( &start_tk.span, "Expected 'break' at start of break statement" )
				return nil
			}

			break_stmnt := new_node( BreakStmnt, start_tk.span )

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after break statement" )
				return nil
			}

			return break_stmnt
		case .Return:
			if !try_consume_tk( file_data, .Return ) {
				log_spanned_error( &start_tk.span, "Expected 'return' at start of return statement" )
				return nil
			}

			return_stmnt := new_node( ReturnStmnt, start_tk.span )
			return_stmnt.expr = parse_expr( file_data, true )

			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) {
				log_spanned_error( &sc_tk.span, "Expected ';' to terminate return statement" )
				return nil
			}

			return return_stmnt
		case:
			expr  := parse_expr( file_data )
			if expr == nil do return nil

			stmnt := new_node( ExprStmnt, expr.span )
			stmnt.expr = expr

			should_term_with_sc := should_expr_terminate_with_semicolon( expr )
			sc_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Semicolon ) && should_term_with_sc {
				log_spanned_error( &sc_tk.span, "Expected terminating ';' after expression statement" )
				return nil
			}

			return stmnt
	}
}

should_expr_terminate_with_semicolon :: proc( e: ^Expr ) -> bool
{
	#partial switch _ in e.derived_expr {
		case ^IfExpr, ^ForLoop, ^WhileLoop, ^InfiniteLoop: return false
		case: return true
	}
}

parse_scope :: proc( file_data: ^FileData, parent_scope: ^Scope ) -> ^Scope
{
	l_curly_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .LCurly ) {
		log_spanned_error( &l_curly_tk.span, "Expected '{' at start of scope" )
		return nil
	}

	consume_newlines( file_data )

	sc := new_node( Scope, l_curly_tk.span )

	tk := curr_tk( file_data )
	for tk.kind != .RCurly {
		stmnt := parse_stmnt( file_data, sc )
		if stmnt == nil do return nil

		append( &sc.stmnts, stmnt )

		consume_newlines( file_data )

		tk = curr_tk( file_data )
	}

	file_data.tk_idx += 1

	return sc
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

parse_var_decl :: proc( file_data: ^FileData, ctx_msg := "variable declaration" ) -> ^VarDecl
{
	start_tk := curr_tk( file_data )
	if !try_consume_tk( file_data, .Ident ) {
		log_spanned_errorf( &start_tk.span, "Expected identifier at start of {:s}", ctx_msg )
		return nil
	}

	type_hint: ^Expr
	default_value: ^Expr

	colon_tk := curr_tk( file_data )
	if try_consume_tk( file_data, .Colon ) {
		type_hint = parse_type( file_data )
		if type_hint == nil do return nil

		if try_consume_tk( file_data, .Assign ) {
			default_value = parse_expr( file_data, true )
			if default_value == nil do return nil
		}
	} else if try_consume_tk( file_data, .ColonAssign ) {
		default_value = parse_expr( file_data, true )
		if default_value == nil do return nil
	}

	var := new_node( VarDecl, start_tk.span )
	var.type_hint = type_hint
	var.default_value = default_value
	var.name = start_tk.str

	return var
}


parse_type :: proc( file_data: ^FileData ) -> ^Expr
{
	return parse_expr( file_data, true )
}


parse_expr :: proc( file_data: ^FileData, is_type := false, last_prio := -1 ) -> ^Expr
{
	lhs := parse_operand( file_data )
	if lhs == nil do return nil

	op_tk := curr_tk( file_data )
	op_prio := bin_op_priority( op_tk )
	can_operate_on := expr_allows_bin_ops( lhs ) && !is_type

	// magic, baby
	if can_operate_on && op_prio > 0 {
		file_data.tk_idx += 1

		rhs: ^Expr
		if op_prio >= last_prio {
			rhs = parse_expr( file_data, false, last_prio = op_prio )
		} else {
			rhs = parse_operand( file_data )
		}

		if rhs == nil do return nil

		span, ok := join_span( &lhs.span, &rhs.span )
		if !ok {
			// TODO(rd): maybe make this better
			return nil // internal compiler error ig
		}

		b_op := new_node( BinOpExpr, span )
		b_op.lhs = lhs
		b_op.rhs = rhs
		b_op.op = op_tk^

		return b_op
	}

	return lhs
}

parse_operand :: proc( file_data: ^FileData ) -> ^Expr
{
	pre := parse_operand_prefix( file_data )
	if pre == nil do return nil

	return parse_operand_postfix( file_data, pre )
}

parse_operand_prefix :: proc( file_data: ^FileData ) -> ^Expr
{
	start_tk := curr_tk( file_data )

	#partial switch start_tk.kind {
		case .Fn:
			file_data.tk_idx += 1

			lp_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .LParen ) {
				log_spanned_error( &lp_tk.span, "Expected '(' to begin procedure prototype parameter definitions" )
				return nil
			}

			proto := new_node( ProcProto, start_tk.span )

			consume_newlines( file_data )

			tk := curr_tk( file_data )

			for tk.kind != .RParen {
				if len( proto.params ) > 0 && !try_consume_tk( file_data, .Comma ) {
					log_spanned_error( &tk.span, "Expected ',' to seperate procedure parameters" )
					return nil
				}

				param := parse_var_decl( file_data, "procedure parameter" )
				if param == nil do return nil

				append( &proto.params, param )

				consume_newlines( file_data )

				tk = curr_tk( file_data )
			}

			// Cosume the ')'
			file_data.tk_idx += 1

			arrow_tk := curr_tk( file_data )
			if arrow_tk.kind == .SmolArrow {
				file_data.tk_idx += 1

				ret_ty := parse_expr( file_data, is_type = true )
				if ret_ty == nil do return nil

				proto.return_type = ret_ty
			}

			consume_newlines( file_data )

			lc_tk := curr_tk( file_data )
			if lc_tk.kind != .LCurly {
				return proto
			}

			sc := parse_scope( file_data, nil )
			if sc == nil do return nil
			
			sc.parent = file_data.mod.file_scope

			proto.body = sc

			return proto
		case .Struct:
			file_data.tk_idx += 1

			l_curly_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .LCurly ) {
				log_spanned_error( &l_curly_tk.span, "Expected '{' at the start of struct body expression" )
				return nil
			}

			struct_expr := new_node( Scope, start_tk.span )
			struct_expr.variant = .Struct
			struct_expr.parent = file_data.mod.file_scope

			consume_newlines( file_data )

			for {
				member := parse_var_decl( file_data, "struct declaration" )
				if member == nil do return nil

				sc_tk := curr_tk( file_data )
				if !try_consume_tk( file_data, .Semicolon ) {
					log_spanned_error( &sc_tk.span, "Expected ';' to terminate struct member declaration" )
					return nil
				}

				append( &struct_expr.stmnts, member )

				consume_newlines( file_data )

				if try_consume_tk( file_data, .RCurly ) {
					break
				}
			}

			return struct_expr
		case .Enum:
			file_data.tk_idx += 1

			l_curly_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .LCurly ) {
				log_spanned_error( &l_curly_tk.span, "Expected '{' at the start of enum body expression" )
				return nil
			}

			enum_expr := new_node( Scope, start_tk.span )
			enum_expr.variant = .Enum
			enum_expr.parent = file_data.mod.file_scope

			consume_newlines( file_data )

			tk := curr_tk( file_data )
			for tk.kind != .RCurly {
				if !try_consume_tk( file_data, .Ident ) {
					log_spanned_error( &tk.span, "Expected ident for enum variant name" )
					return nil
				}

				variant := new_node( EnumVariantDecl, tk.span )
				variant.name = tk.str
				append( &enum_expr.stmnts, variant )

				tk = curr_tk( file_data )
				if !try_consume_tk( file_data, .Semicolon ) {
					log_spanned_error( &tk.span, "Expected ';' to terminate enum variant declaration" )
					return nil
				}

				consume_newlines( file_data )

				tk = curr_tk( file_data )
			}

			file_data.tk_idx += 1

			return enum_expr
		case .Union:
			file_data.tk_idx += 1

			l_curly_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .LCurly ) {
				log_spanned_error( &l_curly_tk.span, "Expected '{' at the start of union body expression" )
				return nil
			}

			union_expr := new_node( Scope, start_tk.span )
			union_expr.variant = .Union
			union_expr.parent = file_data.mod.file_scope

			consume_newlines( file_data )

			tk := curr_tk( file_data )
			for tk.kind != .RCurly {
				if !try_consume_tk( file_data, .Ident ) {
					log_spanned_error( &tk.span, "Expected identifier for union variant name" )
					return nil
				}

				variant := new_node( UnionVariantDecl, tk.span )
				variant.name = tk.str

				tk = curr_tk( file_data )
				if !try_consume_tk( file_data, .LParen ) {
					log_spanned_error( &tk.span, "Expected '(' to begin union variant field list" )
					return nil
				}

				variant.sc = new_node( Scope, tk.span )
				variant.sc.variant = .Struct

				consume_newlines( file_data )

				tk = curr_tk( file_data )
				for tk.kind != .RParen {
					if len( variant.sc.stmnts ) > 0 && !try_consume_tk( file_data, .Comma ) {
						log_spanned_error( &tk.span, "Expected ',' to separate" )
						return nil
					}

					field := parse_var_decl( file_data, "union variant field" )
					if field == nil do return nil

					append( &variant.sc.stmnts, field )

					consume_newlines( file_data )
					tk = curr_tk( file_data )
				}

				file_data.tk_idx += 1

				append( &union_expr.stmnts, variant )

				tk = curr_tk( file_data )
				if !try_consume_tk( file_data, .Semicolon ) {
					log_spanned_error( &tk.span, "Expected ';' to terminate union variant" )
					return nil
				}

				consume_newlines( file_data )

				tk = curr_tk( file_data )
			}

			file_data.tk_idx += 1

			return union_expr
		case .LCurly:
			file_data.tk_idx += 1

			lit := new_node( AnonStructLiteralExpr, start_tk.span )

			consume_newlines( file_data )

			tk := curr_tk( file_data )
			for tk.kind != .RCurly {
				v := parse_expr( file_data )

				consume_newlines( file_data )
				tk = curr_tk( file_data )
			}

			file_data.tk_idx += 1;

			return lit
		case .If:
			if_exp := new_node( IfExpr, start_tk.span )

			curr_if := if_exp
			for {
				if try_consume_tk( file_data, .If ) {
					cond := parse_expr( file_data )
					if cond == nil do return nil

					curr_if.cond = cond
				}

				consume_newlines( file_data )

				l_curly_tk := curr_tk( file_data )
				if l_curly_tk.kind != .LCurly {
					log_spanned_error( &l_curly_tk.span, "Expected '{' to begin if body" )
					return nil
				}

				// FIXME(rd): need context so that we can actually have hookup
				body := parse_scope( file_data, nil )
				if body == nil do return nil

				curr_if.then = body

				consume_newlines( file_data )

				else_tk := curr_tk( file_data )
				if !try_consume_tk( file_data, .Else ) {
					break
				}

				else_block := new_node( IfExpr, else_tk.span )
				curr_if.else_block = else_block
				curr_if = else_block
			}

			return if_exp
		case .For:
			file_data.tk_idx += 1

			iter_name_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .Ident ) {
				log_spanned_error( &iter_name_tk.span, "Expected identifier for loop iterator name" )
				return nil
			}
			iter := new_node( Ident, iter_name_tk.span )

			in_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .In ) {
				log_spanned_error( &in_tk.span, "Expected 'in' in for loop expression" )
				return nil
			}

			range_expr := parse_expr( file_data )
			if range_expr == nil do return nil

			consume_newlines( file_data )

			l_curly_tk := curr_tk( file_data )
			if l_curly_tk.kind != .LCurly {
				log_spanned_error( &l_curly_tk.span, "Expected '{' to begin for loop body" )
				return nil
			}

			// FIXME(rd): need context so that we can actually have hookup
			body := parse_scope( file_data, nil )
			if body == nil do return nil

			for_loop := new_node( ForLoop, start_tk.span )
			for_loop.iter_ident = iter
			for_loop.range = range_expr
			for_loop.body = body

			return for_loop
		case .While:
			file_data.tk_idx += 1

			cond := parse_expr( file_data )
			if cond == nil do return nil

			consume_newlines( file_data )

			l_curly_tk := curr_tk( file_data )
			if l_curly_tk.kind != .LCurly {
				log_spanned_error( &l_curly_tk.span, "Expected '{' to begin while loop body" )
				return nil
			}

			// FIXME(rd): need context so that we can actually have hookup
			body := parse_scope( file_data, nil )
			if body == nil do return nil

			while_loop := new_node( WhileLoop, start_tk.span )
			while_loop.cond = cond
			while_loop.body = body

			return while_loop
		case .Loop:
			file_data.tk_idx += 1

			consume_newlines( file_data )

			l_curly_tk := curr_tk( file_data )
			if l_curly_tk.kind != .LCurly {
				log_spanned_error( &l_curly_tk.span, "Expected '{' to begin loop body" )
				return nil
			}

			// FIXME(rd): need context so that we can actually have hookup
			body := parse_scope( file_data, nil )
			if body == nil do return nil

			inf_loop := new_node( InfiniteLoop, start_tk.span )
			inf_loop.body = body

			return inf_loop
		case .Star:
			file_data.tk_idx += 1

			base_type := parse_expr( file_data )
			if base_type == nil do return nil

			ptr_ty := new_node( PointerTypeExpr, start_tk.span )
			ptr_ty.base_type = base_type

			return ptr_ty
		case .Dot:
			file_data.tk_idx += 1

			ise := new_node( ImplicitSelectorExpr, start_tk.span )

			memb := parse_operand( file_data )
			if memb == nil do return nil

			ise.member = memb

			return ise
		case .At, .Bang, .Tilde, .Minus:
			file_data.tk_idx += 1

			rand := parse_operand( file_data )
			if rand == nil do return nil

			op := new_node( UnaryOpExpr, start_tk.span )
			op.op = start_tk^
			op.rand = rand

			return op
		case .LSquare:
			file_data.tk_idx += 1

			lhs := parse_expr( file_data )
			if lhs == nil do return nil

			sep_tk := curr_tk( file_data )
			if try_consume_tk( file_data, .Semicolon ) {
				size_expr := parse_expr( file_data )
				if size_expr == nil do return nil

				r_sq_tk := curr_tk( file_data )
				if !try_consume_tk( file_data, .RSquare ) {
					log_spanned_error( &r_sq_tk.span, "Expected ']' to close array type expression" )
					return nil
				}

				span, ok := join_span( &start_tk.span, &r_sq_tk.span )
				if !ok do return nil

				arr_ty := new_node( ArrayTypeExpr, span )
				arr_ty.base_type = lhs
				arr_ty.size_expr = size_expr

				return arr_ty
			} else if try_consume_tk( file_data, .DotDot ) {
				rhs := parse_expr( file_data )
				if rhs == nil do return nil


				end_bound_tk := curr_tk( file_data )
				include_end_bound: bool
				if try_consume_tk( file_data, .RSquare ) {
					include_end_bound = true
				} else if try_consume_tk( file_data, .RParen ) {
					include_end_bound = false
				} else {
					log_spanned_error( &end_bound_tk.span, "Expected ']' or ')'" )
					return nil
				}

				span, ok := join_span( &start_tk.span, &end_bound_tk.span )
				if !ok do return nil

				range_expr := new_node( RangeExpr, span )
				range_expr.left_bound_inclusive = true
				range_expr.right_bound_inclusive = include_end_bound
				range_expr.lhs = lhs
				range_expr.rhs = rhs

				return range_expr
			} else if !try_consume_tk( file_data, .RSquare ) {
				log_spanned_error( &sep_tk.span, "Expected ']' to close slice type expression" )
				return nil
			}

			slice_ty := new_node( SliceTypeExpr, start_tk.span )
			slice_ty.base_type = lhs

			return slice_ty
		case .LParen:
			lhs := parse_expr( file_data )

			dot_tk := curr_tk( file_data )
			if !try_consume_tk( file_data, .DotDot ) {
				log_spanned_error( &dot_tk.span, "Expected '..' in range expr" )
				return nil
			}

			rhs := parse_expr( file_data )
			if rhs == nil do return nil

			end_bound_tk := curr_tk( file_data )
			include_end_bound: bool
			if try_consume_tk( file_data, .RSquare ) {
				include_end_bound = true
			} else if try_consume_tk( file_data, .RParen ) {
				include_end_bound = false
			} else {
				log_spanned_error( &end_bound_tk.span, "Expected ']' or ')'" )
				return nil
			}

			span, ok := join_span( &start_tk.span, &end_bound_tk.span )
			if !ok do return nil

			range_expr := new_node( RangeExpr, span )
			range_expr.left_bound_inclusive = false
			range_expr.right_bound_inclusive = include_end_bound
			range_expr.lhs = lhs
			range_expr.rhs = rhs

			return range_expr
		case .Void,    .Bool,   .U8,
		     .I8,      .U16,    .I16,
		     .U32,     .I32,    .U64,
		     .I64,     .USize,  .ISize,
		     .F32,     .F64,    .String,
		     .CString, .RawPtr, .Range:
			file_data.tk_idx += 1
			prim := new_node( PrimitiveTypeExpr, start_tk.span )
			prim.prim = type_prim_kind_from_tk( start_tk.kind )
			return prim
		case .Ident:
			file_data.tk_idx += 1

			peek_tk := curr_tk( file_data )
			if try_consume_tk( file_data, .LCurly ) {
				lit := new_node( NamedStructLiteralExpr, start_tk.span )

				consume_newlines( file_data )

				tk := curr_tk( file_data )
				for tk.kind != .RCurly {
					v := parse_expr( file_data )
					append( &lit.vals, v )

					consume_newlines( file_data )
					tk = curr_tk( file_data )
				}

				return lit
			} else if try_consume_tk( file_data, .LParen ) {
				call := new_node( ProcCallExpr, start_tk.span )

				consume_newlines( file_data )

				tk := curr_tk( file_data )
				for tk.kind != .RParen {
					if len( call.params ) > 0 && !try_consume_tk( file_data, .Comma ) {
						log_spanned_error( &tk.span, "Expected ',' to separate procedure arguments" )
						return nil
					}

					consume_newlines( file_data )

					param := parse_expr( file_data )
					if param == nil do return nil

					append( &call.params, param )

					consume_newlines( file_data )
					tk = curr_tk( file_data )
				}

				file_data.tk_idx += 1

				return call
			}

			ident := new_node( Ident, start_tk.span )
			ident.name = start_tk.str

			return ident
		case .StringLiteral:
			file_data.tk_idx += 1
			str_lit := new_node( StringLiteralExpr, start_tk.span )
			return str_lit
		case .Number:
			file_data.tk_idx += 1
			n_lit := new_node( NumberLiteralExpr, start_tk.span )
			return n_lit
		case:
			log_spanned_errorf( &start_tk.span, "Invalid token in operand: {}", start_tk.kind )
			return nil
	}
}

parse_operand_postfix :: proc( file_data: ^FileData, prefix: ^Expr ) -> ^Expr
{
	consume_newlines( file_data )
	tk := curr_tk( file_data )

	#partial switch tk.kind {
		case .Dot:
			file_data.tk_idx += 1

			access := new_node( MemberAccessExpr, tk.span )
			access.val = prefix

			memb := parse_operand( file_data )
			if memb == nil do return nil

			access.member = memb
			return access
	}

	return prefix
}

expr_allows_bin_ops :: proc( expr: ^Expr ) -> bool
{
	#partial switch _ in expr.derived_expr {
		case ^Scope, ^IfExpr,
		     ^ForLoop, ^WhileLoop,
		     ^InfiniteLoop, ^RangeExpr,
		     ^PointerTypeExpr, ^SliceTypeExpr,
		     ^ArrayTypeExpr:
			return false
		case: return true
	}
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

consume_newlines :: proc( file_data: ^FileData )
{
	for try_consume_tk( file_data, .EndOfLine ) { }
}
