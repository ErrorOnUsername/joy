#include "parser.hh"
#include <cassert>

#include "ast.hh"
#include "compiler.hh"
#include "log.hh"
#include "profiling.hh"


Parser::Parser()
	: lex_info()
	, seen_tokens()
	, node_arena( 16 * 1024 )
	, type_arena( 16 * 1024 )
{
}


void Parser::process_module( std::string const& path )
{
	TIME_PROC();

	bool did_create;
	working_module = Compiler_FindOrAddModule( path, did_create );
	assert( working_module && !did_create ); // FIXME: Assert and nicely fail (shouldn't really be possible to hit this anyways)

	{
		// Initialize the module with the global scope
		Scope* root_scope = working_module->scope_arena.alloc<Scope>();
		working_module->root_scope = root_scope;

		current_scope = root_scope;
	}


	lex_info = FileManager_GetOrCreateFileInfo( path.c_str() );
	// seed with first token
	seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	consume_newlines();

	TIME_SCOPE( "parsing top-level statements" );

	Token tk = curr_tk();
	while ( tk.kind != TK::EndOfFile )
	{
		switch ( tk.kind )
		{
			case TK::DirectiveLoad:
			{
				Span start_span = tk.span;

				tk = next_tk();
				if (tk.kind != TK::StringLiteral)
				{
					log_span_fatal( tk.span, "Expected string-literal after '#load' directive, but got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				size_t last_slash_pos = path.find_last_of( '/' );
				std::string current_dir;
				if ( last_slash_pos == std::string::npos )
				{
					current_dir = "./";
				}
				else
				{
					current_dir = path.substr( 0, last_slash_pos + 1 );
				}

				std::string load_path = current_dir + tk.str;

				tk = next_tk();
				if ( tk.kind != TK::Semicolon )
				{
					log_span_fatal( tk.span, "Expected terminating ';' after module name in '#load' directive, but got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				Span full_span = join_span( start_span, tk.span );

				Module* mod = Compiler_ScheduleLoad( load_path );
				if ( !mod )
				{
					log_span_fatal( full_span, "Module at path '%s' either doesn't exist or is a directory", load_path.c_str() );
				}

				next_tk();
				break;
			}
			case TK::KeywordLet:
				parse_let_stmnt();
				break;
			case TK::KeywordDecl:
				parse_decl_stmnt();
				break;
			default:
				log_span_fatal( tk.span, "Expected 'decl', 'let', or a directive, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}

		consume_newlines();
		tk = curr_tk();
	}
}


enum class DeclStmntKind : uint8_t {
	Invalid,
	Constant,
	Procedure,
	Struct,
	Enum,
	Union,
};


static DeclStmntKind decl_stmnt_kind_from_token_kind( TokenKind kind )
{
	switch ( kind )
	{
		case TK::LParen:        return DeclStmntKind::Procedure;
		case TK::KeywordStruct: return DeclStmntKind::Struct;
		case TK::KeywordEnum:   return DeclStmntKind::Enum;
		case TK::KeywordUnion:  return DeclStmntKind::Union;
		default:                return DeclStmntKind::Constant;
	}

	return DeclStmntKind::Invalid;
}


void Parser::parse_decl_stmnt()
{
	TIME_PROC();

	Token name_tk = next_tk();
	size_t name_tk_idx = tk_idx;

	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected identifier after 'decl', but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	DeclStmntKind decl_stmnt_kind = DeclStmntKind::Constant;

	Token colon_tk = next_tk();
	if ( colon_tk.kind != TK::ColonAssign )
	{
		if ( colon_tk.kind != TK::Colon )
		{
			log_span_fatal( colon_tk.span, "Expected after identifer 'decl' statement's name, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
		}

		Token determinant_tk = next_tk();
		decl_stmnt_kind = decl_stmnt_kind_from_token_kind( determinant_tk.kind );
	}

	// Reset the index to the same so that the parsing code has access to all the proper context
	tk_idx = name_tk_idx;

	switch ( decl_stmnt_kind )
	{
		case DeclStmntKind::Constant:  parse_constant_decl();  break;
		case DeclStmntKind::Procedure: parse_procedure_decl(); break;
		case DeclStmntKind::Struct:    parse_struct_decl();    break;
		case DeclStmntKind::Enum:      parse_enum_decl();      break;
		case DeclStmntKind::Union:     parse_union_decl();     break;
		case DeclStmntKind::Invalid:
			log_span_fatal( name_tk.span, "How did this happen???" );
	}
}


void Parser::parse_let_stmnt()
{
	TIME_PROC();

	Token let_tk = curr_tk();
	if ( let_tk.kind != TK::KeywordLet )
	{
		log_span_fatal( let_tk.span, "Expected 'let' at beginning of let statement, but got '%s'", Token_GetKindAsString( let_tk.kind ) );
	}

	next_tk();

	AstNode* decl = (AstNode*)parse_var_decl( "variable declaration" );

	Token semicolon_tk = curr_tk();
	if ( semicolon_tk.kind != TK::Semicolon )
	{
		log_span_fatal( semicolon_tk.span, "Expected terminating ';' after variable declaration, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
	}

	current_scope->statements.append( decl );

	next_tk();
}


void Parser::parse_if_stmnt()
{
	TIME_PROC();

	Token if_tk = curr_tk();
	next_tk();

	AstNode* condition_expr = parse_expr();

	IfStmnt* stmnt = node_arena.alloc<IfStmnt>();
	stmnt->kind           = AstNodeKind::IfStmnt;
	stmnt->span           = join_span( if_tk.span, condition_expr->span );
	stmnt->condition_expr = condition_expr;

	consume_newlines();

	stmnt->then_block = parse_lexical_scope();

	AstNode* as_node = (AstNode*)stmnt;
	current_scope->statements.append( as_node );

	IfStmnt* last_stmnt = stmnt;

	for ( ;; )
	{
		Token maybe_else_tk = curr_tk();
		if ( maybe_else_tk.kind != TK::KeywordElse )
		{
			break;
		}

		AstNode* else_condition_expr = nullptr;

		Token maybe_if_tk = next_tk();
		if ( maybe_if_tk.kind == TK::KeywordIf )
		{
			next_tk();

			else_condition_expr = parse_expr();
		}

		IfStmnt* else_stmnt = node_arena.alloc<IfStmnt>();
		if ( else_condition_expr )
		{
			else_stmnt->span = join_span( maybe_else_tk.span, else_condition_expr->span );
		}
		else
		{
			else_stmnt->span = maybe_else_tk.span;
		}

		consume_newlines();
		else_stmnt->condition_expr = else_condition_expr;
		else_stmnt->then_block     = parse_lexical_scope();

		last_stmnt->else_stmnt = else_stmnt;
		last_stmnt = else_stmnt;

		if ( !else_condition_expr )
		{
			break;
		}
	}
}


void Parser::parse_for_stmnt()
{
	TIME_PROC();

	Token for_tk = curr_tk();
	if ( for_tk.kind != TK::KeywordFor )
	{
		log_span_fatal( for_tk.span, "Expected 'for' at the start of a for loop statement, but got '%s'", Token_GetKindAsString( for_tk.kind ) );
	}

	Token iter_name_tk = next_tk();
	if ( iter_name_tk.kind != TK::Ident )
	{
		log_span_fatal( iter_name_tk.span, "Expected iterator name identifier but got, '%s'", Token_GetKindAsString( iter_name_tk.kind ) );
	}

	IterName iter;
	iter.name = iter_name_tk.str;

	Token maybe_colon_tk = next_tk();
	if ( maybe_colon_tk.kind == TK::Colon )
	{
		next_tk();

		iter.type = parse_type();
	}

	Token in_tk = curr_tk();
	if ( in_tk.kind != TK::KeywordIn )
	{
		log_span_fatal( in_tk.span, "Expected 'in' after iterator name, but got '%s'", Token_GetKindAsString( in_tk.kind ) );
	}

	next_tk();

	AstNode* range = parse_expr();
	if ( range->kind != AstNodeKind::Range )
	{
		log_span_fatal( range->span, "Expected range expression after iterator name definition" );
	}

	ForLoopStmnt* stmnt = node_arena.alloc<ForLoopStmnt>();
	stmnt->kind  = AstNodeKind::ForLoop;
	stmnt->span  = join_span( for_tk.span, range->span );
	stmnt->iter  = iter;
	stmnt->range = (RangeExpr*)range;
	stmnt->body  = parse_lexical_scope();

	AstNode* as_node = (AstNode*)stmnt;
	current_scope->statements.append( as_node );
}


void Parser::parse_while_stmnt()
{
	TIME_PROC();

	Token while_tk = curr_tk();
	if ( while_tk.kind != TK::KeywordWhile )
	{
		log_span_fatal( while_tk.span, "Expected 'while' at beginning of while statement, but got '%s'", Token_GetKindAsString( while_tk.kind ) );
	}

	next_tk();

	AstNode* condition_expr = parse_expr();

	WhileLoopStmnt* stmnt = node_arena.alloc<WhileLoopStmnt>();
	stmnt->kind           = AstNodeKind::WhileLoop;
	stmnt->span           = join_span( while_tk.span, condition_expr->span );
	stmnt->condition_expr = condition_expr;

	stmnt->body = parse_lexical_scope();

	AstNode* as_node = (AstNode*)stmnt;
	current_scope->statements.append( as_node );
}


void Parser::parse_loop_stmnt()
{
	TIME_PROC();

	Token loop_tk = curr_tk();
	if ( loop_tk.kind != TK::KeywordLoop )
	{
		log_span_fatal( loop_tk.span, "Expected 'loop' at the start of an infinite loop statement, but got '%s'", Token_GetKindAsString( loop_tk.kind ) );
	}

	next_tk();

	InfiniteLoopStmnt* stmnt = node_arena.alloc<InfiniteLoopStmnt>();
	stmnt->kind = AstNodeKind::InfiniteLoop;
	stmnt->span = loop_tk.span;
	stmnt->body = parse_lexical_scope();

	AstNode* as_node = (AstNode*)stmnt;
	current_scope->statements.append( as_node );
}


void Parser::parse_continue_stmnt()
{
	TIME_PROC();

	Token continue_tk = curr_tk();
	if ( continue_tk.kind != TK::KeywordContinue )
	{
		log_span_fatal( continue_tk.span, "Expected 'continue' at beginning of continue statement, but got '%s'", Token_GetKindAsString( continue_tk.kind ) );
	}

	Token semicolon_tk = next_tk();
	if ( semicolon_tk.kind != TK::Semicolon )
	{
		log_span_fatal( semicolon_tk.span, "Expected terminating ';' after continue statement, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
	}

	next_tk();

	AstNode* stmnt = node_arena.alloc<AstNode>();
	stmnt->kind = AstNodeKind::ContinueStmnt;
	stmnt->span = continue_tk.span;

	current_scope->statements.append( stmnt );
}


void Parser::parse_break_stmnt()
{
	TIME_PROC();

	Token break_tk = curr_tk();
	if ( break_tk.kind != TK::KeywordBreak )
	{
		log_span_fatal( break_tk.span, "Expected 'break' at beginning of break statement, but got: '%s'", Token_GetKindAsString( break_tk.kind ) );
	}

	Token semicolon_tk = next_tk();
	if ( semicolon_tk.kind != TK::Semicolon )
	{
		log_span_fatal( semicolon_tk.span, "Expected terminating ';' after break statement, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
	}

	AstNode* stmnt = node_arena.alloc<AstNode>();
	stmnt->kind = AstNodeKind::BreakStmnt;

	current_scope->statements.append( stmnt );

	next_tk();
}


void Parser::parse_return_stmnt()
{
	TIME_PROC();

	Token return_tk = curr_tk();
	if ( return_tk.kind != TK::KeywordReturn )
	{
		log_span_fatal( return_tk.span, "Expected 'return' at the start of return statement, but got '%s'", Token_GetKindAsString( return_tk.kind ) );
	}

	AstNode* expr = nullptr;
	Token semicolon_tk = next_tk();
	if ( semicolon_tk.kind != TK::Semicolon )
	{
		expr = parse_expr( true );

		semicolon_tk = curr_tk();
		if ( semicolon_tk.kind != TK::Semicolon )
		{
			log_span_fatal( semicolon_tk.span, "Expected terminating ';' after return statement, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
		}
	}

	next_tk();

	ReturnStmnt* stmnt = node_arena.alloc<ReturnStmnt>();
	stmnt->kind = AstNodeKind::ReturnStmnt;
	stmnt->span = ( expr ) ? join_span( return_tk.span, expr->span ) : return_tk.span;
	stmnt->expr = expr;

	AstNode* as_node = (AstNode*)stmnt;
	current_scope->statements.append( as_node );
}


void Parser::parse_constant_decl()
{
	TIME_PROC();

	VarDeclStmnt* decl = parse_var_decl( "constant declaration" );
	if ( !decl->default_value )
	{
		log_span_fatal( decl->span, "Constants must be initialized to a value" );
	}

	if ( !( decl->flags & AstNodeFlag::Constant ) )
	{
		log_span_fatal( decl->default_value->span, "Constant's cannot be initialized to a potentially non-constant value" );
	}

	Token semicolon_tk = curr_tk();
	if ( semicolon_tk.kind != TK::Semicolon )
	{
		log_span_fatal( semicolon_tk.span, "Expected terminating ';' in constant declaration, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
	}

	current_scope->constants.append( decl );

	next_tk();
}


void Parser::parse_procedure_decl()
{
	TIME_PROC();

	ProcDeclStmnt* decl = node_arena.alloc<ProcDeclStmnt>();
	decl->kind  = AstNodeKind::ProcDecl;
	decl->flags = AstNodeFlag::Decl;

	Token name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected name identifier in procedure declaration, but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	decl->span = name_tk.span;
	decl->name = name_tk.str;

	Token colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after name in procedure declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	Token l_paren_tk = next_tk();
	if ( l_paren_tk.kind != TK::LParen )
	{
		log_span_fatal( l_paren_tk.span, "Expected '(' at beginning of procedure parameter list, but got '%s'", Token_GetKindAsString( l_paren_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	Token tk = curr_tk();
	while ( tk.kind != TK::RParen )
	{
		if ( decl->params.count > 0 )
		{
			if ( tk.kind != TK::Comma )
			{
				log_span_fatal( tk.span, "Expected ',' between procedure parameters, but got '%s'", Token_GetKindAsString( tk.kind ) );
			}

			next_tk();
			consume_newlines();

			tk = curr_tk();
		}

		VarDeclStmnt* param = parse_var_decl( "procedure parameter declaration" );
		decl->params.append( param );

		consume_newlines();
		tk = curr_tk();
	}

	if ( tk.kind != TK::RParen )
	{
		log_span_fatal( tk.span, "Expected terminating ')' in procedure parameter list, but got '%s'", Token_GetKindAsString( tk.kind ) );
	}

	tk = next_tk();

	if ( tk.kind == TK::ThinArrow )
	{
		tk = next_tk();

		while ( tk.kind != TK::LCurly )
		{
			if ( decl->return_types.count > 0 )
			{
				if ( tk.kind != TK::Comma )
				{
					log_span_fatal( tk.span, "Expected ',' to seperate procedure return types, but got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				next_tk();
			}

			Type* type = parse_type();

			decl->return_types.append( type );

			consume_newlines();
			tk = curr_tk();
		}
	}

	consume_newlines();

	tk = curr_tk();

	// FIXME: handle foreign funciton importing
	decl->body = parse_lexical_scope();

	current_scope->procedures.append( decl );
}


void Parser::parse_struct_decl()
{
	TIME_PROC();

	StructDeclStmnt* decl = node_arena.alloc<StructDeclStmnt>();
	decl->kind  = AstNodeKind::StructDecl;
	decl->flags = AstNodeFlag::Decl;

	//
	// decl MyStruct : struct {
	//      ^~~~ we should be looking here
	//

	Token name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected identifier name after 'decl' in struct declaration, but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	decl->name = name_tk.str;
	decl->span = name_tk.span; // Set the struct span to just the name for nice printing

	//
	// decl MyStruct : struct {
	//               ^~~~ new we should be here
	//

	Token colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after struct name in struct declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyStruct : struct {
	//                 ^~~~ this should be what we're looking at
	//

	Token struct_tk = next_tk();
	if ( struct_tk.kind != TK::KeywordStruct )
	{
		log_span_fatal( struct_tk.span, "Expected 'struct' keyword in struct declaration, but got '%s'", Token_GetKindAsString( struct_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	//
	// decl MyStruct : struct {
	//                        ^~~~ this should be where we're at now
	//
	// decl MyStruct : struct
	// {
	// ^~~~ It doesn't have to be on the same line either
	//
	Token l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected '{' after 'struct' identifer in struct declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	// Now we need to start reading the members
	Token tk = curr_tk();
	while ( tk.kind != TK::RCurly )
	{
		VarDeclStmnt* member = parse_var_decl( "struct member declaration" );

		tk = curr_tk();
		if ( tk.kind != TK::Semicolon )
		{
			log_span_fatal( tk.span, "Expected terminating ';' in struct member declaration, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}

		decl->members.append( member );

		next_tk();
		consume_newlines();

		tk = curr_tk();
	}

	if ( tk.kind != TK::RCurly )
	{
		// This should not even be possible, but we'll check just in case
		log_span_fatal( tk.span, "Expected '}' to terminate struct literal, but got '%s'", Token_GetKindAsString( tk.kind ) );
	}

	next_tk();

	if ( decl->members.count == 0 )
	{
		log_warn( "struct '%s' doesn't have any data members", decl->name.c_str() );
	}
}


void Parser::parse_enum_decl()
{
	TIME_PROC();

	EnumDeclStmnt* decl = node_arena.alloc<EnumDeclStmnt>();
	decl->kind  = AstNodeKind::EnumDecl;
	decl->flags = AstNodeFlag::Decl;

	//
	// decl MyEnum : enum {
	//      ^~~~ we should be looking here
	//

	Token name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected identifier name after 'decl' in enum declaration, but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	decl->name = name_tk.str;
	decl->span = name_tk.span; // Set the struct span to just the name for nice printing

	//
	// decl MyEnum : enum {
	//             ^~~~ new we should be here
	//

	Token colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after enum name in enum declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyEnum : enum {
	//               ^~~~ this should be what we're looking at
	//

	Token enum_tk = next_tk();
	if ( enum_tk.kind != TK::KeywordEnum )
	{
		log_span_fatal( enum_tk.span, "Expected 'enum' keyword in enum declaration, but got '%s'", Token_GetKindAsString( enum_tk.kind ) );
	}

	//
	// decl MyEnum : enum {
	//                    ^~~~ we're looking here right now, but it could also be on another line
	//

	next_tk();
	consume_newlines();

	Token l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected a '{' after the 'enum' keyword in enum declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	//
	// Could be one of the following:
	//
	// 1. decl MyEnum : enum {
	//        Variant;
	//
	// 2. decl MyEnum : enum {
	//        Variant = 1;
	//

	next_tk();
	consume_newlines();

	uint64_t pos = 0;

	Token tk = curr_tk();
	while ( tk.kind != TK::RCurly )
	{
		EnumVariant variant;

		//
		// 1. decl MyEnum : enum {
		//        Variant;
		//        ^~~~ we're looking here
		//
		// 2. decl MyEnum : enum {
		//        Variant = 1;
		//        ^~~~ or here
		//

		if ( tk.kind != TK::Ident )
		{
			log_span_fatal( tk.span, "Expected variant name in enum declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
		}

		variant.span = tk.span;
		variant.name = tk.str;

		tk = next_tk();
		if ( tk.kind == TK::Assign )
		{
			//
			// 2. decl MyEnum : enum {
			//        Variant = 1;
			//                ^~~~ we should now be in this position
			//

			next_tk();

			// TODO: Verify that the expression parsing code works as expected here

			AstNode* val_expr = parse_expr();
			if ( val_expr->kind != AstNodeKind::IntegerLiteral )
			{
				log_span_fatal( val_expr->span, "Enum variant values must be integer literals" );
			}

			variant.val = (IntegerLiteralExpr*)val_expr;
			pos         = variant.val->data;

			tk = curr_tk();
		}
		else
		{
			IntegerLiteralExpr* val_expr = node_arena.alloc<IntegerLiteralExpr>();
			val_expr->kind  = AstNodeKind::IntegerLiteral;
			val_expr->span  = variant.span;
			val_expr->flags = AstNodeFlag::NumberLiteral;
			val_expr->data  = pos;

			variant.val = val_expr;
		}

		if ( tk.kind != TK::Semicolon )
		{
			log_span_fatal( tk.span, "Expected ';' to terminate enum variant, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}

		next_tk();
		consume_newlines();

		tk = curr_tk();

		decl->variants.append( variant );
		pos++;
	}

	if ( tk.kind != TK::RCurly )
	{
		// This should not be possible to trigger, but lets leave it just in case ig :)
		log_span_fatal( tk.span, "Expected enum declaration to be terminated with a '}', but got '%s'", Token_GetKindAsString( tk.kind ) );
	}

	next_tk();

	if ( decl->variants.count == 0 )
	{
		log_warn( "Enum '%s' has no variants", decl->name.c_str() );
	}
}


void Parser::parse_union_decl()
{
	TIME_PROC();

	UnionDeclStmnt* decl = node_arena.alloc<UnionDeclStmnt>();
	decl->kind  = AstNodeKind::UnionDecl;
	decl->flags = AstNodeFlag::Decl;

	//
	// decl MyUnion : union {
	//      ^~~~ we're here
	//
	Token name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected name identifer in union declaration, but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	decl->span = name_tk.span;
	decl->name = name_tk.str;

	//
	// decl MyUnion : union {
	//              ^~~~ we should now be here
	//
	Token colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after name in union declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyUnion : union {
	//                ^~~~ now we're here
	//
	Token union_tk = next_tk();
	if ( union_tk.kind != TK::KeywordUnion )
	{
		log_span_fatal( union_tk.span, "Expected 'union' after ':' in union declaration, but got '%s'", Token_GetKindAsString( union_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	//
	// decl MyUnion : union {
	//                      ^~~~ should be here (could be on a new line)
	//
	Token l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected '{' after 'union' in union declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	Token tk = curr_tk();
	while ( tk.kind != TK::RCurly )
	{
		//
		// decl MyUnion : union {
		//     Variant;
		//     ^~~~ could be here
		//
		// decl MyUnion : union {
		//     Variant( member_a: ilong, member_b: flong );
		//     ^~~~ Could also be this
		//
		if ( tk.kind != TK::Ident )
		{
			log_span_fatal( tk.span, "Expected identifier for union variant name, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}

		UnionVariant variant;
		variant.span = tk.span;
		variant.name = tk.str;

		tk = next_tk();
		if ( tk.kind == TK::LParen )
		{
			//
			// decl MyUnion : union {
			//     Variant( member_a: ilong, member_b: flong );
			//            ^~~~ Should definitely be here (could be empty, in which case we throw a warning)
			//
			tk = next_tk();
			while ( tk.kind != TK::RParen )
			{
				if ( variant.members.count > 0 )
				{
					if ( tk.kind != TK::Comma )
					{
						log_span_fatal( tk.span, "Expected ',' between variant member declarations, but got '%s'", Token_GetKindAsString( tk.kind ) );
					}

					tk = next_tk();
				}

				VarDeclStmnt* member = node_arena.alloc<VarDeclStmnt>();
				member->kind  = AstNodeKind::UnionVariantMember;
				member->flags = AstNodeFlag::Decl;

				if ( tk.kind != TK::Ident )
				{
					log_span_fatal( tk.span, "Expected identifer name in varient member list, got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				member->span = tk.span;
				member->name = tk.str;

				tk = next_tk();
				if ( tk.kind != TK::Colon )
				{
					log_span_fatal( tk.span, "Expected ':' after variant name identifer, but got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				next_tk();

				Type* variant_member_type = parse_type();
				member->type = variant_member_type;

				variant.members.append( member );

				tk = curr_tk();
			}

			if ( tk.kind != TK::RParen )
			{
				log_span_fatal( tk.span, "Expected ')' to terminate variant member list, but got '%s'", Token_GetKindAsString( tk.kind ) );
			}

			next_tk();
		}

		//
		// decl MyUnion : union {
		//     Variant( member_a: ilong, member_b: flong );
		//                                                ^~~~ Now we're at the end
		//
		tk = curr_tk();
		if ( tk.kind != TK::Semicolon )
		{
			log_span_fatal( tk.span, "Expected terminating ';' in union variant declaration, but got '%s'", Token_GetKindAsString( tk.kind ) );
		}

		decl->variants.append( variant );

		next_tk();
		consume_newlines();

		tk = curr_tk();
	}

	if ( tk.kind != TK::RCurly )
	{
		log_span_fatal( tk.span, "Expected union declaration to be terminated with '}', but got '%'", Token_GetKindAsString( tk.kind ) );
	}

	next_tk();
}


LexicalBlock* Parser::parse_lexical_scope()
{
	TIME_PROC();

	Token l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected '{' at start of lexical block, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	LexicalBlock* block = node_arena.alloc<LexicalBlock>();
	block->kind = AstNodeKind::LexicalBlock;
	block->span = l_curly_tk.span;

	{
		Scope* new_scope = working_module->scope_arena.alloc<Scope>();
		new_scope->parent = current_scope;

		current_scope = new_scope;
		block->scope  = new_scope;
	}

	Token tk = curr_tk();
	while ( tk.kind != TK::RCurly )
	{
		switch ( tk.kind )
		{
			case TK::KeywordDecl:     parse_decl_stmnt(); break;
			case TK::KeywordLet:      parse_let_stmnt(); break;
			case TK::KeywordIf:       parse_if_stmnt(); break;
			case TK::KeywordFor:      parse_for_stmnt(); break;
			case TK::KeywordWhile:    parse_while_stmnt(); break;
			case TK::KeywordLoop:     parse_loop_stmnt(); break;
			case TK::KeywordContinue: parse_continue_stmnt(); break;
			case TK::KeywordBreak:    parse_break_stmnt(); break;
			case TK::KeywordReturn:   parse_return_stmnt(); break;
			case TK::LCurly:
			{
				AstNode* parsed_block = (AstNode*)parse_lexical_scope();

				current_scope->statements.append( parsed_block );
				break;
			}
			default:
			{
				AstNode* expr = parse_expr( true, true );

				tk = curr_tk();
				if ( tk.kind != TK::Semicolon )
				{
					log_span_fatal( tk.span, "Expected terminating ';' after expression, but got '%s'", Token_GetKindAsString( tk.kind ) );
				}

				current_scope->statements.append( expr );

				next_tk();
				break;
			}
		}

		consume_newlines();
		tk = curr_tk();
	}

	if ( tk.kind != TK::RCurly )
	{
		log_span_fatal( tk.span, "Expected terminating '}' in lexical block, but got '%s'", Token_GetKindAsString( tk.kind ) );
	}

	next_tk();

	assert( current_scope->parent );
	current_scope = current_scope->parent;

	return block;
}


VarDeclStmnt* Parser::parse_var_decl( char const* usage_in_str )
{
	TIME_PROC();

	VarDeclStmnt* decl = node_arena.alloc<VarDeclStmnt>();
	decl->kind  = AstNodeKind::VarDecl;
	decl->flags = AstNodeFlag::Decl;

	Token name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected name identifier in %s got '%s'", usage_in_str, Token_GetKindAsString( name_tk.kind ) );
	}

	decl->span = name_tk.span;
	decl->name = name_tk.str;

	Token colon_tk = next_tk();
	if ( colon_tk.kind == TK::Colon )
	{
		next_tk();

		Type* type = parse_type();

		Token eq_tk = curr_tk();
		if ( eq_tk.kind == TK::Assign )
		{
			next_tk();

			AstNode* val_expr = parse_expr( true );
			decl->default_value = val_expr;
		}
	}
	else if ( colon_tk.kind == TK::ColonAssign )
	{
		next_tk();

		AstNode* val_expr = parse_expr( true );
		decl->default_value = val_expr;
	}
	else
	{
		log_span_fatal( colon_tk.span, "Expected ':' or ':=' after name identifer in %s, but got '%s'", usage_in_str, Token_GetKindAsString( colon_tk.kind ) );
	}

	return decl;
}


AstNode* Parser::parse_expr( bool can_construct, bool can_assign )
{
	TIME_PROC();

	BinaryOperationExpr* expr = nullptr;

	Token start_tk = curr_tk();


	AstNode* lhs = parse_operand( can_construct );

	for ( ;; )
	{
		consume_newlines();

		Token     op_tk       = curr_tk();
		BinOpKind op          = BinaryOperator_FromTK( op_tk );
		int       op_priority = BinaryOperator_GetPriority( op );

		if ( op == BinaryOpKind::Invalid )
		{
			return ( expr ) ? expr : lhs;
		}

		next_tk();

		if ( op == BinaryOpKind::Range )
		{
			if ( expr )
			{
				log_span_fatal( op_tk.span, "Operating on a range is not valid" );
			}

			RangeExpr* range = node_arena.alloc<RangeExpr>();
			range->kind = AstNodeKind::Range;

			range->lhs = lhs;

			range->rhs = parse_operand( can_construct );

			range->span = join_span( range->lhs->span, range->rhs->span );
			range->flags = range->lhs->flags & range->rhs->flags;

			return range;
		}
		else if ( !expr )
		{
			expr = node_arena.alloc<BinaryOperationExpr>();
			expr->kind = AstNodeKind::BinaryOperation;
		}

		expr->op_kind = op;
		expr->lhs     = lhs;

		consume_newlines();

		size_t start_operand_idx = tk_idx;
		expr->rhs = parse_operand( can_construct );

		consume_newlines();

		Token    peek_op_tk = curr_tk();
		BinOpKind peek_op    = BinaryOperator_FromTK( peek_op_tk );
		if ( peek_op != BinaryOpKind::Invalid )
		{
			int peek_op_priority = BinaryOperator_GetPriority( peek_op );

			if ( peek_op_priority > op_priority )
			{
				tk_idx = start_operand_idx;

				AstNode* subtree = parse_expr( can_construct, can_assign );

				// This means that the previous rhs is now an orphaned node
				// TODO: Maybe track how much memory we waste because of this,
				//       or perhaps reword this logic such that this doesn't
				//       occur?
				expr->rhs = subtree;

				expr->span  = join_span( expr->lhs->span, expr->rhs->span );
				expr->flags = expr->lhs->flags & expr->rhs->flags;
			}
			else
			{
				expr->span  = join_span( expr->lhs->span, expr->rhs->span );
				expr->flags = expr->lhs->flags & expr->rhs->flags;

				lhs = expr;

				expr       = node_arena.alloc<BinaryOperationExpr>();
				expr->kind = AstNodeKind::BinaryOperation;
			}
		}
		else
		{
			expr->span  = join_span( expr->lhs->span, expr->rhs->span );
			expr->flags = expr->lhs->flags & expr->rhs->flags;
		}
	}

	return expr;
}


AstNode* Parser::parse_operand( bool can_construct )
{
	TIME_PROC();

	AstNode* prefix = nullptr;

	Token lead_tk = curr_tk();
	switch ( lead_tk.kind )
	{
		case TK::LSquare:
		{
			next_tk();

			AstNode* expr = parse_expr();
			if ( expr->kind != AstNodeKind::Range )
			{
				log_span_fatal( expr->span, "Expected a range expression, but got something else" );
			}

			RangeExpr* as_range = (RangeExpr*)expr;
			as_range->is_left_bound_included = true; // We started with a '[' so we know its inclusive at the start

			Token end_bound_tk = curr_tk();
			if ( end_bound_tk.kind != TK::RParen && end_bound_tk.kind != TK::RSquare )
			{
				log_span_fatal( end_bound_tk.span, "Expected a ']' or ')' bound-inclusivity specifier after range expression, but got '%s'", Token_GetKindAsString( end_bound_tk.kind ) );
			}

			if ( end_bound_tk.kind == TK::RSquare )
			{
				as_range->is_right_bound_included = true;
			}
			else
			{
				as_range->is_right_bound_included = false;
			}

			next_tk();

			prefix = (AstNode*)as_range;
			break;
		}
		case TK::LParen:
		{
			next_tk();

			AstNode* expr = parse_expr();
			if ( expr->kind == AstNodeKind::Range )
			{
				RangeExpr* as_range = (RangeExpr*)expr;
				as_range->is_left_bound_included = false; // We started with a '(' so we know its exclusive at the start

				Token end_bound_tk = curr_tk();
				if ( end_bound_tk.kind != TK::RParen && end_bound_tk.kind != TK::RSquare )
				{
					log_span_fatal( end_bound_tk.span, "Expected a ']' or ')' bound-inclusivity specifier after range expression, but got '%s'", Token_GetKindAsString( end_bound_tk.kind ) );
				}

				if ( end_bound_tk.kind == TK::RSquare )
				{
					as_range->is_right_bound_included = true;
				}
				else
				{
					as_range->is_right_bound_included = false;
				}

				next_tk();

				prefix = (AstNode*)as_range;
			}
			else
			{
				Token r_paren_tk = curr_tk();
				if ( r_paren_tk.kind != TK::RParen )
				{
					log_span_fatal( r_paren_tk.span, "Expected terminating ')', but got '%s'", Token_GetKindAsString( r_paren_tk.kind ) );
				}

				prefix = expr;
				next_tk();
			}
			break;
		}
		case TK::Star:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::Dereference;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::Ampersand:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::AddressOf;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::Bang:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::LogicalNot;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::Tilde:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::BitwiseNot;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::PlusPlus:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::PrefixIncrement;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::MinusMinus:
		{
			next_tk();

			AstNode* expr = parse_expr();

			UnaryOperationExpr* un_op = node_arena.alloc<UnaryOperationExpr>();
			un_op->kind    = AstNodeKind::UnaryOperation;
			un_op->span    = join_span( lead_tk.span, expr->span );
			un_op->op_kind = UnaryOpKind::PrefixDecrement;
			un_op->operand = expr;

			prefix = (AstNode*)un_op;
			break;
		}
		case TK::Number:
		{
			next_tk();

			Number& number = lead_tk.number;
			switch( number.kind )
			{
				case NumKind::Integer:
				{
					IntegerLiteralExpr* expr = node_arena.alloc<IntegerLiteralExpr>();
					expr->kind  = AstNodeKind::IntegerLiteral;
					expr->flags = AstNodeFlag::IntegerLiteral;
					expr->span  = lead_tk.span;
					expr->data  = number.inum;

					prefix = expr;
					break;
				}
				case NumKind::FloatingPoint:
				{
					FloatingPointLiteralExpr* expr = node_arena.alloc<FloatingPointLiteralExpr>();
					expr->kind  = AstNodeKind::FloatingPointLiteral;
					expr->flags = AstNodeFlag::FloatingPointLiteral;
					expr->span  = lead_tk.span;
					expr->value = number.fnum;

					prefix = expr;
					break;
				}
			}

			break;
		}
		case TK::Ident:
		{
			Array<std::string> name;

			Token tk = curr_tk();
			Span start_span = tk.span;

			for ( ;; )
			{
				name.append( tk.str );

				tk = next_tk();
				if ( tk.kind != TK::DoubleColon )
				{
					break;
				}

				tk = next_tk();
				if ( tk.kind != TK::Ident )
				{
					break;
				}
			}

			switch ( tk.kind )
			{
				case TK::LCurly:
				{
					// im sorry. this is very dumb but im just too tired to deal with this
					if ( !can_construct ) goto USE_AS_IDENT_LABEL;

					int a = 0;

					log_span_fatal( tk.span, "Implement structure literals" );
					break;
				}
				case TK::LParen:
				{
					Array<AstNode*> params;
					Span end_name_span = peek_tk( -1 ).span;

					next_tk();
					consume_newlines();

					tk = curr_tk();
					while ( tk.kind != TK::RParen )
					{
						if ( params.count > 0 )
						{
							if ( tk.kind != TK::Comma )
							{
								log_span_fatal( tk.span, "Expected ',' between procedure parameters, but got '%s'", Token_GetKindAsString( tk.kind ) );
							}

							next_tk();
							consume_newlines();

							tk = curr_tk();
						}

						AstNode* param = parse_expr( true );
						params.append( param );

						tk = curr_tk();
					}

					if ( tk.kind != TK::RParen )
					{
						log_span_fatal( tk.span, "Expected terminating ')' after procedure parameter list, but got '%s'", Token_GetKindAsString( tk.kind ) );
					}

					next_tk();

					ProcCallExpr* expr = node_arena.alloc<ProcCallExpr>();
					expr->kind = AstNodeKind::ProcCall;
					expr->span = join_span( start_span, end_name_span );
					expr->name_path.swap( name );
					expr->params.swap( params );

					prefix = expr;
					break;
				}
				default:
				{
				USE_AS_IDENT_LABEL:
					VarRefExpr* expr = node_arena.alloc<VarRefExpr>();
					expr->kind = AstNodeKind::VarRef;
					expr->span = join_span( start_span, peek_tk( -1 ).span );
					expr->name_path.swap( name );

					prefix = expr;
				}
			}
			break;
		}
		case TK::StringLiteral:
		{
			next_tk();

			StringLiteralExpr* expr = node_arena.alloc<StringLiteralExpr>();
			expr->kind  = AstNodeKind::StringLiteral;
			expr->flags = AstNodeFlag::StringLiteral;
			expr->span  = lead_tk.span;
			expr->value = lead_tk.str;

			prefix = expr;
			break;
		}
		default:
			log_span_fatal( lead_tk.span, "Unexpected token '%s' at start of operand", Token_GetKindAsString( lead_tk.kind ) );
	}

	AstNode* fnl = prefix;

	Token tail_tk = curr_tk();
	switch( tail_tk.kind )
	{
		case TK::PlusPlus:
		{
			next_tk();

			UnaryOperationExpr* expr = node_arena.alloc<UnaryOperationExpr>();
			expr->kind    = AstNodeKind::UnaryOperation;
			expr->span    = join_span( prefix->span, tail_tk.span );
			expr->flags   = prefix->flags;
			expr->op_kind = UnaryOpKind::PostfixIncrement;

			fnl = (AstNode*)expr;
			break;
		}
		case TK::MinusMinus:
		{
			next_tk();

			UnaryOperationExpr* expr = node_arena.alloc<UnaryOperationExpr>();
			expr->kind    = AstNodeKind::UnaryOperation;
			expr->span    = join_span( prefix->span, tail_tk.span );
			expr->flags   = prefix->flags;
			expr->op_kind = UnaryOpKind::PostfixDecrement;

			fnl = (AstNode*)expr;
			break;
		}
		case TK::LSquare:
			log_span_fatal( tail_tk.span, "Implement array indexing" );
			break;
	}

	assert( fnl );

	return fnl;
}


Type* Parser::parse_type()
{
	TIME_PROC();
	Type* ty = type_arena.alloc<Type>();

	Token tk = curr_tk();
	switch ( tk.kind )
	{
		case TK::Star:
		{
			//
			// let some_var: *int;
			//               ^~~~ we're looking here
			//

			next_tk();

			//
			// let some_var: *int;
			//                ^~~~ now we're looking here
			//

			Type* underlying = parse_type();

			//
			// let some_var: *int;
			//                   ^~~~ parse_type() should leave us here
			//

			ty->kind       = TypeKind::Pointer;
			ty->span       = join_span( tk.span, underlying->span );
			ty->underlying = underlying;
			break;
		}
		case TK::LSquare:
		{
			//
			// let some_arr: [int; 0];
			//               ^~~~ we start here
			//

			next_tk();

			//
			// let some_arr: [int; 0];
			//                ^~~~ now we're here
			//

			Type* underlying = parse_type();

			ty->kind       = TypeKind::Array;
			ty->underlying = underlying;

			//
			// let some_arr: [int; 0];
			//                   ^~~~ pare_type() should leave us here
			//

			Token semicolon_tk = curr_tk();
			if ( semicolon_tk.kind != TK::Semicolon )
			{
				log_span_fatal( semicolon_tk.span, "Expected ';' after array underlying type specifier, but got '%s'", Token_GetKindAsString( semicolon_tk.kind ) );
			}

			next_tk();

			//
			// let some_arr: [int; 0];
			//                     ^~~~ now we should be looking at the size expression
			//

			AstNode* size_expr = parse_expr();
			ty->size_expr      = size_expr;

			//
			// let some_arr: [int; 0];
			//                      ^~~~ parse_expr() should leave us right here
			//

			Token close_square_bracket = curr_tk();
			if ( close_square_bracket.kind != TK::RSquare )
			{
				log_span_fatal( close_square_bracket.span, "Expected ']' after array size expression, but got '%s'", Token_GetKindAsString( close_square_bracket.kind ) );
			}

			next_tk();

			//
			// let some_arr: [int; 0];
			//                       ^~~~ now we just eat the terminating ']'
			//

			ty->span = join_span( tk.span, close_square_bracket.span );
			break;
		}
		case TK::Ident:
		{
			ty->kind = TypeKind::NamedUnknown;
			Span final_span;

			//
			// We could be looking at one of two things:
			//  1:  let some_thing: MyType;
			//                      ^~~~ just a normal type name
			//
			//  2:  let some_thing: OtherModuleAlias::OtherType;
			//                      ^~~~ or a type that's guarded by an import alias name
			//

			Token maybe_ns_char = next_tk();
			if ( maybe_ns_char.kind == TK::DoubleColon )
			{
				//
				// let some_thing: OtherModuleAlias::OtherType;
				//                                 ^~~~ we're looking at this right now
				//

				Token type_name_tk = next_tk();
				if ( type_name_tk.kind != TK::Ident )
				{
					log_span_fatal( type_name_tk.span, "Expected type name after namespace alias, but got '%s'", Token_GetKindAsString( type_name_tk.kind ) );
				}

				//
				// let some_thing: OtherModuleAlias::OtherType;
				//                                   ^~~~ now we're here
				//

				ty->import_alias = tk.str;
				ty->name         = type_name_tk.str;
				final_span       = join_span( tk.span, type_name_tk.span );

				next_tk();

				//
				// let some_thing: OtherModuleAlias::OtherType;
				//                                            ^~~~ We have to make sure to leave the cursor after the last token
				//
			}
			else
			{
				final_span = tk.span;
				ty->name   = tk.str;
			}

			ty->span = final_span;
			break;
		}
		case TK::PrimitiveNothing:
			ty->kind = TypeKind::PrimitiveNothing;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveBool:
			ty->kind = TypeKind::PrimitiveBool;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveChar:
			ty->kind = TypeKind::PrimitiveChar;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveU8:
			ty->kind = TypeKind::PrimitiveU8;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveI8:
			ty->kind = TypeKind::PrimitiveI8;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveU16:
			ty->kind = TypeKind::PrimitiveU16;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveI16:
			ty->kind = TypeKind::PrimitiveI16;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveU32:
			ty->kind = TypeKind::PrimitiveU32;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveI32:
			ty->kind = TypeKind::PrimitiveI32;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveU64:
			ty->kind = TypeKind::PrimitiveU64;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveI64:
			ty->kind = TypeKind::PrimitiveI64;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveF32:
			ty->kind = TypeKind::PrimitiveF32;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveF64:
			ty->kind = TypeKind::PrimitiveF64;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveRawPtr:
			ty->kind = TypeKind::PrimitiveRawPtr;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveString:
			ty->kind = TypeKind::PrimitiveString;
			ty->span = tk.span;

			next_tk();
			break;
		case TK::PrimitiveCString:
			ty->kind = TypeKind::PrimitiveCString;
			ty->span = tk.span;

			next_tk();
			break;
		default:
			log_span_fatal( tk.span, "Expected '*', '[', or an identifier at start of type name, but got '%s'", Token_GetKindAsString( tk.kind ) );
	}

	return ty;
}


void Parser::consume_newlines()
{
	TIME_PROC();

	Token curr = curr_tk();

	while ( curr.kind == TK::EndOfLine )
	{
		curr = next_tk();
	}
}


Token Parser::peek_tk( int offset )
{
	TIME_PROC();

	size_t idx = (size_t)( std::max( (int)tk_idx + offset, 0 ) );

	if ( idx > tk_idx )
	{
		for ( size_t i = tk_idx; i < idx; i++ )
		{
			if ( i >= seen_tokens.size() )
				seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );
			else
				seen_tokens[i] = Lexer_GetNextToken( lex_info );
		}
	}

	return seen_tokens[idx];
}


Token Parser::curr_tk()
{
	TIME_PROC();

	return peek_tk( 0 );
}


Token Parser::next_tk()
{
	TIME_PROC();

	tk_idx++;

	if ( tk_idx >= seen_tokens.size() )
		seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	return seen_tokens[tk_idx];
}
