#include "parser.hh"
#include <iostream>

#include "ast.hh"
#include "compiler.hh"
#include "job_system.hh"
#include "profiling.hh"
#include "program.hh"

Parser::Parser( Module* working_module, std::vector<Token>& token_stream, std::string const& directory )
	: m_token_stream( token_stream )
	, m_idx( 0 )
	, m_current_scope( 0 )
	, m_working_module( working_module )
{
	m_working_module->directory = directory;

	Scope root_scope { };
	root_scope.parent = -1;
	m_working_module->scopes.emplace_back( std::move( root_scope ) );
}


void Parser::parse_module()
{
	TIME_PROC();

	Token tk = current();
	while ( tk.kind != TK_EOF )
	{
		eat_whitespace();
		tk = current();

		switch ( tk.kind )
		{
			case TK_KW_DECL:
			{
				parse_decl_stmnt();
				break;
			}
			case TK_CD_LOAD:
			{
				eat_current_specific( TK_CD_LOAD );

				Token module_path_tk = current();
				if ( module_path_tk.kind != TK_STR_LIT )
					Compiler::panic( module_path_tk.span, "Expected string literal path after '#load' directive, got: '%s'\n", tk_as_str( module_path_tk.kind ) );

				eat_current_specific( TK_STR_LIT );
				eat_current_specific( TK_SEMICOLON );

				std::string path = m_working_module->directory + module_path_tk.str;

				Module* module = Program::get_or_add_module( path );
				assert( module );

				// TODO: warn multiple includes
				m_working_module->imports.insert( module );

				CompileJob job = {
					.filepath = path,
					.module   = module,
					.proc     = Compiler::compile_module_job,
				};

				JobSystem::enqueue_job( job );
				break;
			}
			default:
				Compiler::panic( tk.span, "Syntax Error! Unexpected token: %s\n", tk_as_str( tk.kind ) );
		};

		eat_whitespace();
		tk = current();
	}
}

Stmnt* Parser::parse_statement()
{
	TIME_PROC();

	eat_whitespace();

	Token tk = current();
	switch ( tk.kind )
	{
		case TK_KW_LET:
		{
			parse_let_stmnt();
			break;
		}
		case TK_KW_IF:       return parse_if_stmnt();
		case TK_KW_FOR:      return parse_for_stmnt();
		case TK_KW_WHILE:    return parse_while_stmnt();
		case TK_KW_LOOP:     return parse_loop_stmnt();
		case TK_KW_CONTINUE: return parse_continue_stmnt();
		case TK_KW_BREAK:    return parse_break_stmnt();
		case TK_KW_RETURN:   return parse_return_stmnt();
		default:             return parse_expr_stmnt();
	}

	eat_whitespace();

	// Some stmnts don't need to be added to the ast (like VarDecls) since
	// they're stored somewhere else and will be reference in other ways by
	// traversing the lexical scopes and returning the index they're actually
	// stored at.
	return nullptr;
}

Expr* Parser::parse_expr( bool can_assign, bool allow_newlines )
{
	TIME_PROC();

	BinOpExpr* expr = nullptr;

	int64_t last_operator_priority = 100'000;

	eat_whitespace();

	// FIXME: ADD EXPR SPANS
	Span start_span = current().span;

	Expr*      lhs       = parse_operand();
	BinOpExpr* as_bin_op = (BinOpExpr*)lhs;

	for ( ;; )
	{
		eat_whitespace();

		Token rator = current();
		if ( !is_tk_operator( rator.kind ) )
		{
			if ( expr ) return expr;
			else return lhs;
		}
		m_idx++;

		BinOpKind op = tk_as_operator( rator.kind );
		int64_t op_prio = op_priority( op );

		if ( op == B_OP_RANGE )
		{
			// If expr isn't null that means that we have a partial tree already, which
			// makes this state illegal.
			if ( expr )
				Compiler::panic( rator.span, "Syntax Error! Operating on a range in not allowed\n" );

			RangeExpr* range = (RangeExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( RangeExpr ) );
			range->kind      = EXPR_RANGE;
			range->lhs       = lhs;

			eat_whitespace();

			range->rhs = parse_operand();

			Span end_span = peek( -1 ).span;
			range->span   = join_span( start_span, end_span );

			eat_whitespace();

			if ( is_tk_operator( current().kind ) )
				Compiler::panic( current().span, "Syntax Error! Operating on a range is not allowed\n" );

			return range;
		}
		else if ( !expr )
		{
			expr = (BinOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( BinOpExpr ) );
			expr->kind = EXPR_BIN_OP;
		}

		expr->op_kind = op;
		expr->lhs     = lhs;

		eat_whitespace();

		size_t start_operand_idx = m_idx;
		Expr*  rhs               = parse_operand();

		expr->rhs = rhs;

		eat_whitespace();

		Token peek_op = current();
		if ( is_tk_operator( peek_op.kind ) )
		{
			BinOpKind peek_op_kind = tk_as_operator( peek_op.kind );
			int64_t   peek_op_prio = op_priority( peek_op_kind );

			if ( peek_op_prio > op_prio )
			{
				// Reset to before that way we correctly parse, while perserving op order
				m_idx = start_operand_idx;

				// We have an expression subtree we need to assemble first
				Expr* subtree = parse_expr( false, true );

				expr->rhs = (Expr*)subtree;
			}
			else
			{
				lhs = expr;

				expr = (BinOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( BinOpExpr ) );
				expr->kind = EXPR_BIN_OP;
			}
		}
		else
		{
			break;
		}

		Span end_span = peek( -1 ).span;
		expr->span = join_span( start_span, end_span );
	}

	Span end_span = peek( -1 ).span;
	expr->span = join_span( start_span, end_span );

	return expr;
}

void Parser::parse_decl_stmnt()
{
	TIME_PROC();

	Token tk = current();

	Span start_span = tk.span;

	Token name = next();
	if ( name.kind != TK_IDENT )
		Compiler::panic( name.span, "Syntax Error! Expected identifier, got: %s\n", tk_as_str( name.kind ) );

	eat_next_specific( TK_COLON );

	Token determinant = current();
	Span  fnl_span    = join_span( start_span, determinant.span );

	switch ( determinant.kind )
	{
		case TK_KW_STRUCT:
		{
			auto members = parse_struct_members();

			StructDeclStmnt decl{ };
			decl.span    = fnl_span;
			decl.kind    = STMNT_STRUCT_DECL;
			decl.name    = name.str;
			decl.members = std::move( members );

			m_working_module->structs.emplace_back( std::move( decl ) );
			break;
		}
		case TK_KW_ENUM:
		case TK_KW_UNION:
			TODO();
		case TK_L_PAREN:
		{
			auto params = parse_proc_decl_param_list();

			eat_current_specific( TK_R_PAREN );

			TypeID return_type_id = -1;

			Token maybe_arrow = current();
			if ( maybe_arrow.kind == TK_THIN_ARROW )
			{
				eat_current_specific( TK_THIN_ARROW );

				Type raw_type = parse_raw_type();
				return_type_id = register_type( raw_type );
			}
			else
			{
				Type nothing_type;
				nothing_type.kind = TY_NOTHING;
				nothing_type.size = 0;

				return_type_id = register_type( nothing_type );
			}

			auto   body       = parse_stmnt_block();
			size_t root_scope = body.scope_id;

			for ( auto const& p : params )
			{
				Scope& current_scope = m_working_module->scopes[root_scope];
				if ( current_scope.vars_id_map.contains( p.name ) )
				{
					VarDeclStmnt var = m_working_module->vars[current_scope.vars_id_map[p.name]];
					Compiler::panic( var.span, "Error! Found variable declaration in scope with the same name as parameter: %s\n", p.name.c_str() );
				}
			}

			ProcDeclStmnt decl{ };
			decl.span             = fnl_span;
			decl.kind             = STMNT_PROC_DECL;
			decl.name             = name.str;
			decl.params           = std::move(params);
			decl.return_type      = return_type_id;
			decl.body             = std::move(body);
			decl.linkage          = PROC_LINKAGE_INTERNAL;
			decl.linking_lib_name = "";

			m_working_module->procs.emplace_back( std::move( decl ) );
			break;
		}
		default:
			break;
	};
}

void Parser::parse_let_stmnt()
{
	TIME_PROC();

	Token tk         = current();
	Span  start_span = tk.span;

	Token name = next();
	if ( name.kind != TK_IDENT )
		Compiler::panic( name.span, "Syntax Error! Expected identifer in variable declaration, got: %s\n", tk_as_str( name.kind ) );

	Span fnl_span = join_span( start_span, name.span );

	VarDeclStmnt var{ };
	var.span     = fnl_span;
	var.kind     = STMNT_VAR_DECL;
	var.scope_id = 0;
	var.name     = name.str;

	Token colon_or_autotype = next();
	if ( colon_or_autotype.kind == TK_COLON )
	{
		Type   raw_type = parse_raw_type();
		TypeID type     = register_type( raw_type );

		var.type = type;
	}
	else if ( colon_or_autotype.kind == TK_COLON_ASSIGN )
	{
		var.type = -1;
	}
	else
	{
		Compiler::panic( colon_or_autotype.span, "Syntax Error! Expected ':' or ':=' in variable declaration, got: %s", tk_as_str( colon_or_autotype.kind ) );
	}

	Token eq_or_semicolon = current();
	if ( eq_or_semicolon.kind == TK_ASSIGN )
	{
		m_idx++;
		var.default_value = parse_expr( false, true );
	}
	else if ( eq_or_semicolon.kind == TK_SEMICOLON )
	{
		var.default_value = nullptr;
	}
	else if ( colon_or_autotype.kind == TK_COLON_ASSIGN )
	{
		m_idx++;
		var.default_value = parse_expr( false, true );
		eat_current_specific( TK_SEMICOLON );
	}
	else
	{
		Compiler::panic( eq_or_semicolon.span, "Syntax Error! Expected '=' or ';' in variable declaraton, got: %s\n", tk_as_str( eq_or_semicolon.kind ) );
	}

	Scope& curr_scope = m_working_module->scopes[m_current_scope];
	if ( curr_scope.vars_id_map.contains( var.name ) )
		Compiler::panic(var.span, "Redefinition of identifier: '%s'\n", var.name.c_str());

	curr_scope.vars_id_map[var.name] = m_working_module->vars.size();
	m_working_module->vars.push_back( var );
}

Stmnt* Parser::parse_if_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_IF );

	Expr* condition = parse_expr( false, true );

	eat_whitespace();

	Block body = parse_stmnt_block();

	eat_whitespace();

	IfStmnt* if_stmnt = (IfStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( IfStmnt ) );
	if_stmnt->kind       = STMNT_IF;
	if_stmnt->condition  = condition;
	if_stmnt->body       = std::move(body);
	if_stmnt->else_chain = nullptr;

	if ( current().kind == TK_KW_ELSE )
	{
		eat_current_specific( TK_KW_ELSE );

		eat_whitespace();

		if ( current().kind == TK_KW_IF )
		{
			if_stmnt->else_chain = parse_statement();
		}
		else
		{
			IfStmnt* else_stmnt = (IfStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( IfStmnt ) );
			else_stmnt->kind       = STMNT_IF;
			else_stmnt->condition  = nullptr;
			else_stmnt->body       = parse_stmnt_block();
			else_stmnt->else_chain = nullptr;
		}
	}

	return if_stmnt;
}

Stmnt* Parser::parse_for_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_FOR );

	Token iter_name = current();
	if ( iter_name.kind != TK_IDENT )
		Compiler::panic( iter_name.span, "Syntax Error! Expected identifier for loop iterator name, got: %s\n", tk_as_str( iter_name.kind ) );

	eat_next_specific( TK_KW_IN );

	Expr* range = parse_expr( false, true );
	if ( range->kind != EXPR_RANGE )
		Compiler::panic( range->span, "Syntax Error! Expected a range expression, got something else." );

	eat_whitespace();

	Block  body       = parse_stmnt_block();
	Scope& root_scope = m_working_module->scopes[body.scope_id];

	if ( root_scope.vars_id_map.contains( iter_name.str ) )
	{
		VarDeclStmnt& var = m_working_module->vars[root_scope.vars_id_map[iter_name.str]];
		Compiler::panic( var.span, "Error! Found variable declaration in scope with the same name as iterator: %s\n", iter_name.str.c_str() );
	}

	eat_whitespace();

	VarDeclStmnt iter { };
	iter.scope_id      = body.scope_id;
	iter.name          = iter_name.str;
	iter.type          = -1;
	iter.default_value = ((RangeExpr*)range)->lhs;

	root_scope.vars_id_map[iter.name] = m_working_module->vars.size();
	m_working_module->vars.push_back( iter );

	ForLoopStmnt* for_loop = (ForLoopStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( ForLoopStmnt ) );
	for_loop->kind  = STMNT_FOR;
	for_loop->it    = { iter.name, (VarID)m_working_module->vars.size() - 1 };
	for_loop->range = (RangeExpr*)range;
	for_loop->body  = std::move( body );

	return for_loop;
}

Stmnt* Parser::parse_while_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_WHILE );

	Expr* condition = parse_expr( false, true );

	eat_whitespace();

	Block body = parse_stmnt_block();

	eat_whitespace();

	WhileLoopStmnt* while_loop = (WhileLoopStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( WhileLoopStmnt ) );
	while_loop->kind      = STMNT_WHILE;
	while_loop->condition = condition;
	while_loop->body      = std::move( body );

	return while_loop;
}

Stmnt* Parser::parse_loop_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_LOOP );

	eat_whitespace();

	Block body = parse_stmnt_block();

	eat_whitespace();

	LoopStmnt* loop_stmnt = (LoopStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( LoopStmnt ) );
	loop_stmnt->kind = STMNT_LOOP;
	loop_stmnt->body = std::move( body );

	return loop_stmnt;
}

Stmnt* Parser::parse_continue_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_CONTINUE );

	Stmnt* continue_stmnt = (Stmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( Stmnt ) );
	continue_stmnt->kind = STMNT_CONTINUE;

	eat_current_specific( TK_SEMICOLON );
	eat_whitespace();

	return continue_stmnt;
}

Stmnt* Parser::parse_break_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_BREAK );

	Stmnt* break_stmnt = (Stmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( Stmnt ) );
	break_stmnt->kind = STMNT_BREAK;

	eat_current_specific( TK_SEMICOLON );
	eat_whitespace();

	return break_stmnt;
}

Stmnt* Parser::parse_return_stmnt()
{
	TIME_PROC();

	eat_current_specific( TK_KW_RETURN );

	Expr* ret_val = parse_expr( false, true );
	eat_current_specific( TK_SEMICOLON );

	eat_whitespace();

	ReturnStmnt* ret_stmnt = (ReturnStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( ReturnStmnt ) );
	ret_stmnt->kind = STMNT_RETURN;
	ret_stmnt->val  = ret_val;

	return ret_stmnt;
}

Stmnt* Parser::parse_expr_stmnt()
{
	TIME_PROC();

	ExprStmnt* expr = (ExprStmnt*)m_working_module->stmnt_arena.alloc_bytes( sizeof( ExprStmnt ) );
	expr->kind = STMNT_EXPR;
	expr->expr = parse_expr( true, true );
	expr->span = expr->expr->span;

	eat_whitespace();
	eat_current_specific( TK_SEMICOLON );
	eat_whitespace();

	return (Stmnt*)expr;
}

Expr* Parser::parse_operand()
{
	TIME_PROC();

	Expr* prefix = nullptr;

	Token lead = current();
	switch ( lead.kind )
	{
		case TK_L_PAREN:
		{
			Span start_span = current().span;
			eat_current_specific( TK_L_PAREN );

			prefix = parse_expr( false, true );

			Token tail = current();
			if ( prefix->kind != EXPR_RANGE && tail.kind != TK_R_PAREN )
			{
				Compiler::panic( tail.span, "Syntax Error! Expected ')' at the end of expr, got: %s\n", tk_as_str( tail.kind ) );
			}
			else if ( prefix->kind == EXPR_RANGE )
			{
				RangeExpr* range = (RangeExpr*)prefix;
				range->is_left_included = false;

				if ( tail.kind == TK_R_PAREN )
					range->is_right_included = false;
				else if ( tail.kind == TK_R_SQUARE )
					range->is_right_included = true;
				else
					Compiler::panic( tail.span, "Syntax Error! Expected terminating range bound (')' or ']'), got: %s\n", tk_as_str( tail.kind ) );
			}

			prefix->span = join_span( start_span, tail.span );

			m_idx++;

			break;
		}
		case TK_L_SQUARE:
		{
			Span start_span = current().span;

			m_idx++;

			prefix = parse_expr( false, true );

			Token tail = current();
			if ( prefix->kind == EXPR_RANGE )
			{
				RangeExpr* range = (RangeExpr*)prefix;
				range->is_left_included = false;

				if ( tail.kind == TK_R_PAREN )
					range->is_right_included = false;
				else if ( tail.kind == TK_R_SQUARE )
					range->is_right_included = true;
				else
					Compiler::panic( tail.span, "Syntax Error! Expected terminating range bound (')' or ']'), got: %s\n", tk_as_str( tail.kind ) );
			}
			else
			{
				Compiler::panic( tail.span, "Syntax Error! Expected range expression, but got '%s'.\n", bin_op_as_str( ( (BinOpExpr*)prefix )->op_kind ) );
			}

			Span end_span = current().span;

			m_idx++;

			prefix->span = join_span( start_span, end_span );

			break;
		}
		case TK_BANG:
		{
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );
			expr->kind    = EXPR_UNARY_OP;
			expr->op_kind = U_OP_L_NOT;

			Expr* rand = parse_expr( false, true );
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_PLUS_PLUS:
		{
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );
			expr->kind    = EXPR_UNARY_OP;
			expr->op_kind = U_OP_PRE_INC;

			Expr* rand = parse_expr( false, true );
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_MINUS_MINUS:
		{
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );
			expr->kind    = EXPR_UNARY_OP;
			expr->op_kind = U_OP_PRE_DEC;

			Expr* rand = parse_expr( false, true );
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_STAR:
		{
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );
			expr->kind    = EXPR_UNARY_OP;
			expr->op_kind = U_OP_DEREF;

			Expr* rand = parse_expr( false, true );
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_DOLLAR:
		{
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );
			expr->kind    = EXPR_UNARY_OP;
			expr->op_kind = U_OP_ADDR_OF;

			Expr* rand = parse_expr( false, true );
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_IDENT:
		{
			if ( peek().kind == TK_L_PAREN )
			{
				Token current_tk = current();

				std::string proc_name       = current_tk.str;
				Span        start_call_span = current_tk.span;

				eat_next_specific( TK_L_PAREN );

				eat_whitespace();

				std::vector<Expr*> params;
				while ( current().kind != TK_R_PAREN )
				{
					params.push_back( parse_expr( false, true ) );

					Token t = current();
					eat_whitespace();
					if ( t.kind == TK_COMMA )
						eat_current_specific( TK_COMMA );
					else if ( t.kind != TK_R_PAREN )
						Compiler::panic( t.span, "Expected ',' or ')' in procedure call, but got: %s\n", tk_as_str( t.kind ) );
				}

				eat_current_specific( TK_R_PAREN );

				ProcCallExpr* call_expr = (ProcCallExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( ProcCallExpr ) );
				call_expr->kind   = EXPR_PROC_CALL;
				call_expr->span   = start_call_span; // TODO: Is just giving the span of the name enough?
				call_expr->name   = proc_name;
				call_expr->params = params;

				prefix = call_expr;
			}
			else
			{
				VarExpr* var_ref = (VarExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( VarExpr ) );
				var_ref->kind   = EXPR_VAR;
				var_ref->span   = current().span;
				var_ref->name   = current().str;
				var_ref->var_id = get_ident_var_id( var_ref->name );

				m_idx++;

				prefix = var_ref;
			}

			break;
		}
		case TK_STR_LIT:
		{
			ConstStringExpr* str = (ConstStringExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( ConstStringExpr ) );
			str->kind = EXPR_STRING;
			str->str  = lead.str;

			m_idx++;

			prefix = str;

			break;
		}
		case TK_NUMBER:
		{
			ConstNumberExpr* number = (ConstNumberExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( ConstNumberExpr ) );
			number->kind = EXPR_NUMBER;
			number->num  = current().number;

			m_idx++;

			prefix = number;

			break;
		}
		case TK_BOOL_T:
		{
			ConstBoolExpr* boolean = (ConstBoolExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( ConstBoolExpr ) );
			boolean->kind  = EXPR_BOOL;
			boolean->value = true;

			m_idx++;

			prefix = boolean;

			break;
		}
		case TK_BOOL_F:
		{
			ConstBoolExpr* boolean = (ConstBoolExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( ConstBoolExpr ) );
			boolean->kind  = EXPR_BOOL;
			boolean->value = false;

			m_idx++;

			prefix = boolean;

			break;
		}
		default:
			Compiler::panic( lead.span, "Syntax Error! Unexpected token in expression: %s", tk_as_str( lead.kind ) );
	}

	Expr* fnl = prefix;

	Token tail = current();
	switch ( tail.kind )
	{
		case TK_PLUS_PLUS:
		{
			UnaryOpExpr* op = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );

			op->kind    = EXPR_UNARY_OP;
			op->op_kind = U_OP_POST_INC;
			op->operand = prefix;

			m_idx++;

			fnl = op;

			break;
		}
		case TK_MINUS_MINUS:
		{
			UnaryOpExpr* op = (UnaryOpExpr*)m_working_module->expr_arena.alloc_bytes( sizeof( UnaryOpExpr ) );

			op->kind    = EXPR_UNARY_OP;
			op->op_kind = U_OP_POST_DEC;
			op->operand = prefix;

			m_idx++;

			fnl = op;

			break;
		}
		default:
			break;
	}

	return fnl;
}

Type Parser::parse_raw_type()
{
	TIME_PROC();

	Token tk = current();
	switch ( tk.kind )
	{
		case TK_STAR:
		{
			m_idx++;

			Type ptr {};
			ptr.kind = TY_PTR;
			ptr.size = -1;

			Type underlying = parse_raw_type();
			ptr.underlying  = register_type( underlying );

			return ptr;
		}
		case TK_L_SQUARE:
		{
			m_idx++;

			Type arr {};
			arr.kind = TY_ARRAY;

			Type underlying = parse_raw_type();
			arr.underlying  = register_type( underlying );

			eat_next_specific( TK_SEMICOLON );

			arr.size_expr = parse_expr( false, true );

			eat_next_specific( TK_R_SQUARE );

			return arr;
		}
		case TK_IDENT:
		{
			m_idx++;

			Type ty {};
			ty.kind = TY_UNKNOWN;
			ty.name = tk.str;
			ty.size = -1;

			return ty;
		}
		case TK_TY_NOTHING:
		{
			m_idx++;

			Type ty {};
			ty.kind = TY_NOTHING;
			ty.name = "$internal$_nothing";
			ty.size = 0;

			return ty;
		}
		case TK_TY_BOOL:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_BOOL;
			ty.name = "$internal$_bool";
			ty.size = 1;

			return ty;
		}
		case TK_TY_CHAR:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_CHAR;
			ty.name = "$internal$_char";
			ty.size = 1;

			return ty;
		}
		case TK_TY_U8:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_U8;
			ty.name = "$internal$_u8";
			ty.size = 1;

			return ty;
		}
		case TK_TY_I8:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_I8;
			ty.name = "$internal$_i8";
			ty.size = 1;

			return ty;
		}
		case TK_TY_U16:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_U16;
			ty.name = "$internal$_u16";
			ty.size = 2;

			return ty;
		}
		case TK_TY_I16:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_I16;
			ty.name = "$internal$_i16";
			ty.size = 2;

			return ty;
		}
		case TK_TY_U32:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_U32;
			ty.name = "$internal$_u32";
			ty.size = 4;

			return ty;
		}
		case TK_TY_I32:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_I32;
			ty.name = "$internal$_i32";
			ty.size = 4;

			return ty;
		}
		case TK_TY_U64:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_U64;
			ty.name = "$internal$_u64";
			ty.size = 8;

			return ty;
		}
		case TK_TY_I64:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_I64;
			ty.name = "$internal$_i64";
			ty.size = 8;

			return ty;
		}
		case TK_TY_F32:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_F32;
			ty.name = "$internal$_f32";
			ty.size = 4;

			return ty;
		}
		case TK_TY_F64:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_F64;
			ty.name = "$internal$_f64";
			ty.size = 8;

			return ty;
		}
		case TK_TY_RAWPTR:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_RAWPTR;
			ty.name = "$internal$_rawptr";
			ty.size = -1;

			return ty;
		}
		case TK_TY_STR:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_STR;
			ty.name = "$internal$_str";
			ty.size = -1;

			return ty;
		}
		case TK_TY_CSTR:
		{
			m_idx++;

			Type ty{};
			ty.kind = TY_CSTR;
			ty.name = "$internal$_cstr";
			ty.size = -1;

			return ty;
		}
		default:
			Compiler::panic( tk.span, "Syntax Error! Unexpected token in typename: %s\n", tk_as_str( tk.kind ) );
	}

	return Type { };
}

TypeID Parser::register_type( Type& type )
{
	TIME_PROC();

	if ( m_working_module->type_id_map.find( type.name ) != m_working_module->type_id_map.end() )
		return m_working_module->type_id_map[type.name];

	m_working_module->types.push_back( type );
	m_working_module->type_id_map[type.name] = m_working_module->types.size() - 1;
	return m_working_module->types.size() - 1;
}

std::vector<StructMember> Parser::parse_struct_members()
{
	TIME_PROC();

	std::vector<StructMember> members;

	eat_current_specific( TK_KW_STRUCT );
	eat_whitespace();
	eat_current_specific( TK_L_CURLY );

	for ( ;; )
	{
		Token name = current();
		if ( name.kind == TK_EOL )
		{
			m_idx++;
			continue;
		}

		if ( name.kind != TK_IDENT )
			Compiler::panic( name.span, "Syntax Error! Expected struct member name, got: %s", tk_as_str( name.kind ) );

		eat_next_specific( TK_COLON );

		Type   raw_type = parse_raw_type();
		TypeID type     = register_type( raw_type );

		eat_current_specific( TK_SEMICOLON );

		members.push_back( StructMember {
			name.str,
			type,
		} );

		eat_whitespace();

		Token end = current();
		if ( end.kind == TK_R_CURLY )
			break;
	}

	eat_current_specific( TK_R_CURLY );

	return members;
}

std::vector<ProcParameter> Parser::parse_proc_decl_param_list()
{
	TIME_PROC();

	std::vector<ProcParameter> params;

	Token curr = current();
	if ( curr.kind != TK_L_PAREN )
		Compiler::panic( curr.span, "Syntax Error! Expected '(', got: %s\n", tk_as_str( curr.kind ) );

	Token tk = next();
	while ( current().kind != TK_R_PAREN )
	{
		Token name = current();
		if ( name.kind != TK_IDENT )
			Compiler::panic( name.span, "Syntax Error! Expected identifier in parameter list, got: %s\n", tk_as_str( name.kind ) );

		eat_next_specific( TK_COLON );

		Type   raw_type = parse_raw_type();
		TypeID type     = register_type( raw_type );

		ProcParameter param{ };
		param.name = name.str;
		param.type = type;
		// TODO: Parse default parameter values once we figure out a good way to express
		//       the acceptance of the default value. (Perhaps passing '_' to indicate
		//       that you want to use the default, rather that forcing you to make it the
		//       last parameter in the funciton.)
		param.default_value = nullptr;

		params.push_back( param );

		Token comma = current();
		if ( comma.kind == TK_COMMA )
		{
			m_idx++;
			continue;
		}
		else if ( comma.kind == TK_R_PAREN )
		{
			break;
		}
		else
		{
			Compiler::panic( comma.span, "Syntax Error! Expected ',' or ')', got: %s", tk_as_str( comma.kind ) );
		}
	}

	return params;
}

Block Parser::parse_stmnt_block()
{
	TIME_PROC();

	std::vector<Stmnt*> stmnts;

	eat_whitespace();

	eat_current_specific( TK_L_CURLY );

	Scope new_scope { };
	new_scope.parent = m_current_scope;

	m_current_scope      = m_working_module->scopes.size();
	ScopeID new_scope_id = m_current_scope;

	m_working_module->scopes.emplace_back( std::move( new_scope ) );

	eat_whitespace();

	Token tk = current();
	while ( tk.kind != TK_R_CURLY )
	{
		Stmnt* stmnt = parse_statement();
		if ( stmnt ) // VarDecls are stored elsewhere, so we dont need to worry about adding them
			stmnts.push_back( stmnt );
		tk = current();
	}

	eat_current_specific( TK_R_CURLY );

	m_current_scope = m_working_module->scopes[new_scope_id].parent;

	return Block{ new_scope_id, std::move( stmnts ) };
}

bool Parser::is_ident_defined( std::string const& name ) const
{
	TIME_PROC();

	ScopeID scope = m_current_scope;
	while ( scope != -1 )
	{
		Scope const& curr_scope = m_working_module->scopes[scope];
		if ( curr_scope.vars_id_map.contains( name ) )
			return true;

		scope = curr_scope.parent;
	}

	return false;
}

VarID Parser::get_ident_var_id( std::string const& name ) const
{
	TIME_PROC();

	ScopeID scope = m_current_scope;
	while ( scope != -1 )
	{
		Scope const& curr_scope = m_working_module->scopes[scope];
		if ( curr_scope.vars_id_map.contains( name ) )
			return curr_scope.vars_id_map.at( name );

		scope = curr_scope.parent;
	}

	return -1;
}

Token Parser::current()
{
	TIME_PROC();

	return peek( 0 );
}

Token Parser::next()
{
	TIME_PROC();

	m_idx++;
	return current();
}

void Parser::eat_next_specific( TokenKind kind )
{
	TIME_PROC();

	Token tk = next();
	m_idx++;
	if ( tk.kind != kind )
		Compiler::panic( tk.span, "Syntax Error! Expected: %s, got %s", tk_as_str( kind ), tk_as_str( tk.kind ) );
}

void Parser::eat_current_specific( TokenKind kind )
{
	TIME_PROC();

	Token tk = current();
	m_idx++;
	if ( tk.kind != kind )
		Compiler::panic( tk.span, "Syntax Error! Expected: %s, got %s", tk_as_str( kind ), tk_as_str( tk.kind ) );
}

void Parser::eat_whitespace()
{
	TIME_PROC();

	Token tk = current();
	while ( tk.kind == TK_EOL )
	{
		tk = next();
	}
}

Token Parser::peek( int64_t offset )
{
	TIME_PROC();

	assert( m_idx + offset < m_token_stream.size() );

	return m_token_stream[m_idx + offset];
}
