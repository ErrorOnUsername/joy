#include "parser.hh"
#include <cassert>

#include "log.hh"
#include "profiling.hh"


Parser::Parser()
	: lex_info()
	, seen_tokens()
	, node_arena( 16 * 1024 )
	, type_arena( 16 * 1024 )
{
}


Module Parser::process_module( std::string const& path )
{
	TIME_PROC();

	Module module;
	{
		// Initialize the module with the global scope
		Scope root_scope { };
		module.scopes.append( root_scope );

		current_scope = &module.scopes[0];
	}


	lex_info = FileManager_GetOrCreateFileInfo( path.c_str() );
	// seed with first token
	seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	consume_newlines();

	TIME_SCOPE( "parsing top-level statements" );

	Token* tk = &curr_tk();
	while ( tk->kind != TK::EndOfFile )
	{
		switch ( tk->kind )
		{
			case TK::DirectiveLoad:
				log_span_fatal( tk->span, "Implement module loading!" );
				break;
			case TK::KeywordLet:
				parse_let_stmnt();
				break;
			case TK::KeywordDecl:
				parse_decl_stmnt();
				break;
			default:
				log_span_fatal( tk->span, "Expected 'decl', 'let', or a directive, but got '%s'", Token_GetKindAsString( tk->kind ) );
		}

		consume_newlines();
		tk = &curr_tk();
	}

	return module;
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

	Token& name_tk = next_tk();
	size_t name_tk_idx = tk_idx;

	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected identifier after 'decl', but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected identifier after constant declaration's name, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	Token& determinant_tk = next_tk();
	DeclStmntKind decl_stmnt_kind = decl_stmnt_kind_from_token_kind( determinant_tk.kind );

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
			log_span_fatal( determinant_tk.span, "Unexpected character in 'decl' stmnt" );
	}
}


void Parser::parse_let_stmnt()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement let parsing" );
}


void Parser::parse_constant_decl()
{
	TIME_PROC();

	Token& tk = curr_tk();
	log_span_fatal( tk.span, "Implement constant parsing" );
}


void Parser::parse_procedure_decl()
{
	TIME_PROC();

	ProcDeclStmnt* decl = node_arena.alloc<ProcDeclStmnt>();
	decl->kind  = AstNodeKind::ProcDecl;
	decl->flags = AstNodeFlag::Decl;

	Token& name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected name identifier in procedure declaration, but got '%s'", Token_GetKindAsString( name_tk.kind ) );
	}

	decl->span = name_tk.span;
	decl->name = name_tk.str;

	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after name in procedure declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	Token& l_paren_tk = next_tk();
	if ( l_paren_tk.kind != TK::LParen )
	{
		log_span_fatal( l_paren_tk.span, "Expected '(' at beginning of procedure parameter list, but got '%s'", Token_GetKindAsString( l_paren_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	Token* tk = &curr_tk();
	while ( tk->kind != TK::RParen )
	{
		if ( decl->params.count > 0 )
		{
			if ( tk->kind != TK::Comma )
			{
				log_span_fatal( tk->span, "Expected ',' between procedure parameters, but got '%s'", Token_GetKindAsString( tk->kind ) );
			}

			next_tk();
			consume_newlines();

			tk = &curr_tk();
		}

		VarDeclStmnt* param = parse_var_decl( "procedure parameter declaration" );
		decl->params.append( param );

		consume_newlines();
		tk = &curr_tk();
	}

	if ( tk->kind != TK::RParen )
	{
		log_span_fatal( tk->span, "Expected terminating ')' in procedure parameter list, but got '%s'", Token_GetKindAsString( tk->kind ) );
	}

	next_tk();
	consume_newlines();

	tk = &curr_tk();

	// FIXME: handle foreign funciton importing

	if ( tk->kind != TK::LCurly )
	{
		log_span_fatal( tk->span, "Expected '{' after parameter list in procedure decaration, but got '%s'", Token_GetKindAsString( tk->kind ) );
	}

	next_tk();
	consume_newlines();

	tk = &curr_tk();
	while ( tk->kind != TK::RCurly )
	{
		switch ( tk->kind )
		{
			case TK::KeywordDecl: parse_decl_stmnt(); break;
			case TK::KeywordLet:  parse_let_stmnt(); break;
			default:
			{
				AstNode* expr = parse_expr();

				tk = &curr_tk();
				if ( tk->kind != TK::Semicolon )
				{
					log_span_fatal( tk->span, "Expected terminating ';' after expression, but got '%s'", Token_GetKindAsString( tk->kind ) );
				}

				current_scope->statement_list.append( expr );

				next_tk();
				break;
			}
		}

		consume_newlines();
		tk = &curr_tk();
	}

	if ( tk->kind != TK::RCurly )
	{
		log_span_fatal( tk->span, "Expected terminating '}' in procedure declaration, but got '%s'", Token_GetKindAsString( tk->kind ) );
	}

	next_tk();
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

	Token& name_tk = curr_tk();
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

	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after struct name in struct declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyStruct : struct {
	//                 ^~~~ this should be what we're looking at
	//

	Token& struct_tk = next_tk();
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
	Token& l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected '{' after 'struct' identifer in struct declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	// Now we need to start reading the members
	Token* tk = &curr_tk();
	while ( tk->kind != TK::RCurly )
	{
		VarDeclStmnt* member = parse_var_decl( "struct member declaration" );

		tk = &curr_tk();
		if ( tk->kind != TK::Semicolon )
		{
			log_span_fatal( tk->span, "Expected terminating ';' in struct member declaration, but got '%s'", Token_GetKindAsString( tk->kind ) );
		}

		decl->members.append( member );

		next_tk();
		consume_newlines();

		tk = &curr_tk();
	}

	if ( tk->kind != TK::RCurly )
	{
		// This should not even be possible, but we'll check just in case
		log_span_fatal( tk->span, "Expected '}' to terminate struct literal, but got '%s'", Token_GetKindAsString( tk->kind ) );
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

	Token& name_tk = curr_tk();
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

	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after enum name in enum declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyEnum : enum {
	//               ^~~~ this should be what we're looking at
	//

	Token& enum_tk = next_tk();
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

	Token& l_curly_tk = curr_tk();
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

	Token* tk = &curr_tk();
	while ( tk->kind != TK::RCurly )
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

		if ( tk->kind != TK::Ident )
		{
			log_span_fatal( tk->span, "Expected variant name in enum declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
		}

		variant.span = tk->span;
		variant.name = tk->str;

		tk = &next_tk();
		if ( tk->kind == TK::Assign )
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

			tk = &curr_tk();
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

		if ( tk->kind != TK::Semicolon )
		{
			log_span_fatal( tk->span, "Expected ';' to terminate enum variant, but got '%s'", Token_GetKindAsString( tk->kind ) );
		}

		next_tk();
		consume_newlines();

		tk = &curr_tk();

		decl->variants.append( variant );
		pos++;
	}

	if ( tk->kind != TK::RCurly )
	{
		// This should not be possible to trigger, but lets leave it just in case ig :)
		log_span_fatal( tk->span, "Expected enum declaration to be terminated with a '}', but got '%s'", Token_GetKindAsString( tk->kind ) );
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
	Token& name_tk = curr_tk();
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
	Token& colon_tk = next_tk();
	if ( colon_tk.kind != TK::Colon )
	{
		log_span_fatal( colon_tk.span, "Expected ':' after name in union declaration, but got '%s'", Token_GetKindAsString( colon_tk.kind ) );
	}

	//
	// decl MyUnion : union {
	//                ^~~~ now we're here
	//
	Token& union_tk = next_tk();
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
	Token& l_curly_tk = curr_tk();
	if ( l_curly_tk.kind != TK::LCurly )
	{
		log_span_fatal( l_curly_tk.span, "Expected '{' after 'union' in union declaration, but got '%s'", Token_GetKindAsString( l_curly_tk.kind ) );
	}

	next_tk();
	consume_newlines();

	Token* tk = &curr_tk();
	while ( tk->kind != TK::RCurly )
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
		if ( tk->kind != TK::Ident )
		{
			log_span_fatal( tk->span, "Expected identifier for union variant name, but got '%s'", Token_GetKindAsString( tk->kind ) );
		}

		UnionVariant variant;
		variant.span = tk->span;
		variant.name = tk->str;

		tk = &next_tk();
		if ( tk->kind == TK::LParen )
		{
			//
			// decl MyUnion : union {
			//     Variant( member_a: ilong, member_b: flong );
			//            ^~~~ Should definitely be here (could be empty, in which case we throw a warning)
			//
			tk = &next_tk();
			while ( tk->kind != TK::RParen )
			{
				if ( variant.members.count > 0 )
				{
					if ( tk->kind != TK::Comma )
					{
						log_span_fatal( tk->span, "Expected ',' between variant member declarations, but got '%s'", Token_GetKindAsString( tk->kind ) );
					}

					tk = &next_tk();
				}

				VarDeclStmnt* member = node_arena.alloc<VarDeclStmnt>();
				member->kind  = AstNodeKind::UnionVariantMember;
				member->flags = AstNodeFlag::Decl;

				if ( tk->kind != TK::Ident )
				{
					log_span_fatal( tk->span, "Expected identifer name in varient member list, got '%s'", Token_GetKindAsString( tk->kind ) );
				}

				member->span = tk->span;
				member->name = tk->str;

				tk = &next_tk();
				if ( tk->kind != TK::Colon )
				{
					log_span_fatal( tk->span, "Expected ':' after variant name identifer, but got '%s'", Token_GetKindAsString( tk->kind ) );
				}

				next_tk();

				Type* variant_member_type = parse_type();
				member->type = variant_member_type;

				variant.members.append( member );

				tk = &curr_tk();
			}

			if ( tk->kind != TK::RParen )
			{
				log_span_fatal( tk->span, "Expected ')' to terminate variant member list, but got '%s'", Token_GetKindAsString( tk->kind ) );
			}

			next_tk();
		}

		//
		// decl MyUnion : union {
		//     Variant( member_a: ilong, member_b: flong );
		//                                                ^~~~ Now we're at the end
		//
		tk = &curr_tk();
		if ( tk->kind != TK::Semicolon )
		{
			log_span_fatal( tk->span, "Expected terminating ';' in union variant declaration, but got '%s'", Token_GetKindAsString( tk->kind ) );
		}

		decl->variants.append( variant );

		next_tk();
		consume_newlines();

		tk = &curr_tk();
	}

	if ( tk->kind != TK::RCurly )
	{
		log_span_fatal( tk->span, "Expected union declaration to be terminated with '}', but got '%'", Token_GetKindAsString( tk->kind ) );
	}

	next_tk();
}


VarDeclStmnt* Parser::parse_var_decl( char const* usage_in_str )
{
	VarDeclStmnt* decl = node_arena.alloc<VarDeclStmnt>();
	decl->kind  = AstNodeKind::VarDecl;
	decl->flags = AstNodeFlag::Decl;

	Token& name_tk = curr_tk();
	if ( name_tk.kind != TK::Ident )
	{
		log_span_fatal( name_tk.span, "Expected name identifier in %s got '%s'", usage_in_str, Token_GetKindAsString( name_tk.kind ) );
	}

	decl->span = name_tk.span;
	decl->name = name_tk.str;

	Token& colon_tk = next_tk();
	if ( colon_tk.kind == TK::Colon )
	{
		next_tk();

		Type* type = parse_type();

		Token& eq_tk = curr_tk();
		if ( eq_tk.kind == TK::Assign )
		{
			next_tk();

			AstNode* val_expr = parse_expr();
			decl->default_value = val_expr;
		}
	}
	else if ( colon_tk.kind == TK::ColonAssign )
	{
		next_tk();

		AstNode* val_expr = parse_expr();
		decl->default_value = val_expr;
	}
	else
	{
		log_span_fatal( colon_tk.span, "Expected ':' or ':=' after name identifer in %s, but got '%s'", usage_in_str, Token_GetKindAsString( colon_tk.kind ) );
	}

	return decl;
}


AstNode* Parser::parse_expr()
{
	Token& tk = curr_tk();
	AstNode* expr = nullptr;

	log_span_fatal( tk.span, "Implement expression parsing" );
	return expr;
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

			Token& semicolon_tk = curr_tk();
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

			Token& close_square_bracket = curr_tk();
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

			Token& maybe_ns_char = next_tk();
			if ( maybe_ns_char.kind == TK::DoubleColon )
			{
				//
				// let some_thing: OtherModuleAlias::OtherType;
				//                                 ^~~~ we're looking at this right now
				//

				Token& type_name_tk = next_tk();
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

	Token* curr = &curr_tk();

	while ( curr->kind == TK::EndOfLine )
	{
		curr = &next_tk();
	}
}


Token& Parser::peek_tk( int offset )
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


Token& Parser::curr_tk()
{
	TIME_PROC();

	return peek_tk( 0 );
}


Token& Parser::next_tk()
{
	TIME_PROC();

	tk_idx++;

	if ( tk_idx >= seen_tokens.size() )
		seen_tokens.push_back( Lexer_GetNextToken( lex_info ) );

	return seen_tokens[tk_idx];
}
