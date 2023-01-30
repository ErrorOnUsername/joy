#include "parser.hh"
#include <iostream>

#include "compiler.hh"

Parser::Parser(std::vector<Token>& token_stream)
	: m_token_stream(token_stream)
	, m_idx(0)
	, m_current_scope(0)
	, m_root_module()
	, m_stmnt_arena(16 * 1024)
	, m_expr_arena(16 * 1024)
{ }

void Parser::parse_module()
{
	m_root_module.scopes.push_back(Scope{ });
	Token tk = current();
	while (tk.kind != TK_EOF) {
		switch (tk.kind) {
			case TK_KW_DECL: {
				Token name = next();
				if (name.kind != TK_IDENT)
					Compiler::panic(name.span, "Syntax Error! Expected identifier, got: %s\n", tk_as_str(name.kind));

				eat_next_specific(TK_COLON);

				Token determinant = current();
				switch (determinant.kind) {
					case TK_KW_STRUCT: {
						auto members = parse_struct_members();

						StructDeclStmnt decl{ };
						decl.kind = STMNT_STRUCT_DECL;
						decl.name = name.str;
						decl.members = std::move(members);

						printf("Struct: %s\n", decl.name.c_str());
						for (auto const& el : decl.members) {
							printf("  %s: %s[%lld]\n", el.name.c_str(), m_root_module.types[el.type].name.c_str(), el.type);
						}

						m_root_module.structs.emplace_back(std::move(decl));
						break;
					}
					case TK_KW_ENUM:
						[[fallthrough]];
					case TK_KW_UNION:
						TODO();
						[[fallthrough]];
					case TK_L_PAREN: {
						auto params = parse_proc_decl_param_list();

						eat_current_specific(TK_R_PAREN);

						auto body = parse_stmnt_block();

						ProcDeclStmnt decl{ };
						decl.kind = STMNT_PROC_DECL;
						decl.name = name.str;
						decl.params = std::move(params);
						decl.body = std::move(body);
						decl.linkage = PROC_LINKAGE_INTERNAL;
						decl.linking_lib_name = "";

						m_root_module.procs.emplace_back(std::move(decl));
						break;
					}
					default:
						break;
				};
				break;
			}
			case TK_CD_LOAD: {
				TODO();
				break;
			}
		};

		tk = next();
	}
}

Stmnt* Parser::parse_statement()
{
	eat_whitespace();

	Token tk = current();
	switch (tk.kind) {
		case TK_KW_LET: {
			Token name = next();
			if (name.kind != TK_IDENT)
				Compiler::panic(name.span, "Syntax Error! Expected identifer in variable declaration, got: %s\n", tk_as_str(name.kind));

			VarDeclStmnt var{ };
			var.kind = STMNT_VAR_DECL;
			var.scope_id = 0;
			var.name = name.str;

			Token colon_or_autotype = next();
			if (colon_or_autotype.kind == TK_COLON) {
				Type raw_type = parse_raw_type();
				TypeID type = register_type(raw_type);

				var.type = type;
			} else if (colon_or_autotype.kind == TK_COLON_ASSIGN) {
				var.type = -1;
			} else {
				Compiler::panic(colon_or_autotype.span, "Syntax Error! Expected ':' or ':=' in variable declaration, got: %s", tk_as_str(colon_or_autotype.kind));
			}

			Token eq_or_semicolon = next();
			if (eq_or_semicolon.kind == TK_ASSIGN) {
				m_idx++;
				var.default_value = parse_expr(false, true);
			}
			else if (eq_or_semicolon.kind == TK_SEMICOLON) {
				var.default_value = nullptr;
			} else if (colon_or_autotype.kind == TK_COLON_ASSIGN) {
				var.default_value = parse_expr(false, true);
				dump_expr(var.default_value, 0);
				eat_current_specific(TK_SEMICOLON);
			} else {
				Compiler::panic(eq_or_semicolon.span, "Syntax Error! Expected '=' or ';' in variable declaraton, got: %s\n", tk_as_str(eq_or_semicolon.kind));
			}

			m_root_module.vars.emplace_back(std::move(var));
			break;
		}
		case TK_KW_IF:
			[[fallthrough]];
		case TK_KW_FOR:
			[[fallthrough]];
		case TK_KW_WHILE:
			[[fallthrough]];
		case TK_KW_LOOP:
			[[fallthrough]];
		case TK_KW_CONTINUE:
			[[fallthrough]];
		case TK_KW_BREAK:
			[[fallthrough]];
		case TK_KW_RETURN:
			TODO();
			break;
		default:
			ExprStmnt* expr = (ExprStmnt*)m_stmnt_arena.alloc_bytes(sizeof(ExprStmnt));
			expr->kind = STMNT_EXPR;
			expr->expr = parse_expr(true, true);

			return (Stmnt*)expr;
	}

	eat_whitespace();

	// Some stmnts don't need to be added to the ast (like VarDecls) since
	// they're stored somewhere else and will be reference in other ways by
	// traversing the lexical scopes and returning the index they're actually
	// stored at.
	return nullptr;
}

Expr* Parser::parse_expr(bool can_assign, bool allow_newlines)
{
	BinOpExpr* expr = nullptr;

	int64_t last_operator_priority = 100'000;

	eat_whitespace();

	Expr* lhs = parse_operand();
	BinOpExpr* as_bin_op = (BinOpExpr*)lhs;

	for (;;) {
		eat_whitespace();

		Token rator = current();
		if (!is_tk_operator(rator.kind)) {
			if (expr) return expr;
			else return lhs;
		}
		m_idx++;

		BinOpKind op = tk_as_operator(rator.kind);
		int64_t op_prio = op_priority(op);

		if (op == B_OP_RANGE) {
			// If expr isn't null that means that we have a partial tree already, which
			// makes this state illegal.
			if (expr)
				Compiler::panic(rator.span, "Syntax Error! Operating on a range in not allowed\n");

			RangeExpr* range = (RangeExpr*)m_expr_arena.alloc_bytes(sizeof(RangeExpr));
			range->kind = EXPR_RANGE;
			range->lhs = lhs;

			eat_whitespace();

			range->rhs = parse_operand();

			eat_whitespace();

			if (is_tk_operator(current().kind))
				Compiler::panic(current().span, "Syntax Error! Operating on a range is not allowed\n");

			return range;
		} else if (!expr) {
			expr = (BinOpExpr*)m_expr_arena.alloc_bytes(sizeof(BinOpExpr));
			expr->kind = EXPR_BIN_OP;
		}

		expr->op_kind = op;
		expr->lhs = lhs;

		eat_whitespace();

		size_t start_operand_idx = m_idx;
		Expr* rhs = parse_operand();
		expr->rhs = rhs;

		eat_whitespace();

		Token peek_op = current();
		if (is_tk_operator(peek_op.kind)) {
			BinOpKind peek_op_kind = tk_as_operator(peek_op.kind);
			int64_t peek_op_prio = op_priority(peek_op_kind);
			if (peek_op_prio > op_prio) {
				// Reset to before that way we correctly parse, while perserving op order
				m_idx = start_operand_idx;

				// We have an expression subtree we need to assemble first
				Expr* subtree = parse_expr(false, true);
				expr->rhs = (Expr*)subtree;
			} else {
				lhs = expr;

				expr = (BinOpExpr*)m_expr_arena.alloc_bytes(sizeof(BinOpExpr));
				expr->kind = EXPR_BIN_OP;
			}
		} else {
			break;
		}
	}

	return expr;
}

Expr* Parser::parse_operand()
{
	Expr* prefix = nullptr;

	Token lead = current();
	switch (lead.kind) {
		case TK_L_PAREN: {
			m_idx++;

			prefix = parse_expr(false, true);

			Token tail = current();
			if (prefix->kind != EXPR_RANGE && tail.kind != TK_R_PAREN)
				Compiler::panic(tail.span, "Syntax Error! Expected ')' at the end of expr, got: %s\n", tk_as_str(tail.kind));
			else if (prefix->kind == EXPR_RANGE) {
				RangeExpr* range = (RangeExpr*)prefix;
				range->is_left_included = false;

				if (tail.kind == TK_R_PAREN)
					range->is_right_included = false;
				else if (tail.kind == TK_R_SQUARE)
					range->is_right_included = true;
				else
					Compiler::panic(tail.span, "Syntax Error! Expected terminating range bound (')' or ']'), got: %s\n", tk_as_str(tail.kind));
			}

			m_idx++;

			break;
		}
		case TK_L_SQUARE: {
			m_idx++;

			prefix = parse_expr(false, true);

			Token tail = current();
			if (prefix->kind == EXPR_RANGE) {
				RangeExpr* range = (RangeExpr*)prefix;
				range->is_left_included = false;

				if (tail.kind == TK_R_PAREN)
					range->is_right_included = false;
				else if (tail.kind == TK_R_SQUARE)
					range->is_right_included = true;
				else
					Compiler::panic(tail.span, "Syntax Error! Expected terminating range bound (')' or ']'), got: %s\n", tk_as_str(tail.kind));
			} else {
				Compiler::panic(tail.span, "Syntax Error! Expected range expression, but got something else.\n");
			}

			break;
		}
		case TK_BANG: {
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));
			expr->kind = EXPR_UNARY_OP;
			expr->op_kind = U_OP_L_NOT;

			Expr* rand = parse_expr(false, true);
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_PLUS_PLUS: {
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));
			expr->kind = EXPR_UNARY_OP;
			expr->op_kind = U_OP_PRE_INC;

			Expr* rand = parse_expr(false, true);
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_MINUS_MINUS: {
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));
			expr->kind = EXPR_UNARY_OP;
			expr->op_kind = U_OP_PRE_DEC;

			Expr* rand = parse_expr(false, true);
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_STAR: {
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));
			expr->kind = EXPR_UNARY_OP;
			expr->op_kind = U_OP_DEREF;

			Expr* rand = parse_expr(false, true);
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_DOLLAR: {
			m_idx++;

			UnaryOpExpr* expr = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));
			expr->kind = EXPR_UNARY_OP;
			expr->op_kind = U_OP_ADDR_OF;

			Expr* rand = parse_expr(false, true);
			expr->operand = rand;

			prefix = expr;

			break;
		}
		case TK_IDENT: {
			VarExpr* var_ref = (VarExpr*)m_expr_arena.alloc_bytes(sizeof(VarExpr));
			var_ref->kind = EXPR_VAR;
			var_ref->name = current().str;

			m_idx++;

			prefix = var_ref;

			break;
		}
		case TK_STR_LIT: {
			ConstStringExpr* str = (ConstStringExpr*)m_expr_arena.alloc_bytes(sizeof(ConstStringExpr));
			str->kind = EXPR_STRING;
			str->str = lead.str;

			m_idx++;

			prefix = str;

			break;
		}
		case TK_NUMBER: {
			ConstNumberExpr* number = (ConstNumberExpr*)m_expr_arena.alloc_bytes(sizeof(ConstNumberExpr));
			number->kind = EXPR_NUMBER;
			number->num = current().number;

			m_idx++;

			prefix = number;

			break;
		}
		case TK_BOOL_T: {
			ConstBoolExpr* boolean = (ConstBoolExpr*)m_expr_arena.alloc_bytes(sizeof(ConstBoolExpr));
			boolean->kind = EXPR_BOOL;
			boolean->value = true;

			m_idx++;

			prefix = boolean;

			break;
		}
		case TK_BOOL_F: {
			ConstBoolExpr* boolean = (ConstBoolExpr*)m_expr_arena.alloc_bytes(sizeof(ConstBoolExpr));
			boolean->kind = EXPR_BOOL;
			boolean->value = false;

			m_idx++;

			prefix = boolean;

			break;
		}
		default:
			Compiler::panic(lead.span, "Syntax Error! Unexpected token in expression: %s", tk_as_str(lead.kind));
	}

	Expr* fnl = prefix;

	Token tail = current();
	switch (tail.kind) {
		case TK_PLUS_PLUS: {
			UnaryOpExpr* op = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));

			op->kind = EXPR_UNARY_OP;
			op->op_kind = U_OP_POST_INC;
			op->operand = prefix;

			m_idx++;

			fnl = op;

			break;
		}
		case TK_MINUS_MINUS: {
			UnaryOpExpr* op = (UnaryOpExpr*)m_expr_arena.alloc_bytes(sizeof(UnaryOpExpr));

			op->kind = EXPR_UNARY_OP;
			op->op_kind = U_OP_POST_DEC;
			op->operand = prefix;

			m_idx++;

			fnl = op;

			break;
		}
	}

	return fnl;
}

Type Parser::parse_raw_type()
{
	Token tk = current();
	switch (tk.kind) {
	case TK_STAR: {
		m_idx++;

		Type ptr {};
		ptr.kind = TY_PTR;
		ptr.size = -1;

		Type underlying = parse_raw_type();
		ptr.underlying = register_type(underlying);

		return ptr;
	}
	case TK_L_SQUARE: {
		m_idx++;

		Type arr {};
		arr.kind = TY_ARRAY;

		Type underlying = parse_raw_type();
		arr.underlying = register_type(underlying);

		eat_next_specific(TK_SEMICOLON);

		arr.size_expr = parse_expr(false, true);

		eat_next_specific(TK_R_SQUARE);

		return arr;
	}
	case TK_IDENT: {
		Type ty {};
		ty.kind = TY_UNKNOWN;
		ty.name = tk.str;
		ty.size = -1;

		return ty;
	}
	case TK_TY_NOTHING: {
		Type ty {};
		ty.kind = TY_NOTHING;
		ty.name = "$internal$_nothing";
		ty.size = 0;

		return ty;
	}
	case TK_TY_BOOL: {
		Type ty{};
		ty.kind = TY_BOOL;
		ty.name = "$internal$_bool";
		ty.size = 1;

		return ty;
	}
	case TK_TY_CHAR: {
		Type ty{};
		ty.kind = TY_CHAR;
		ty.name = "$internal$_char";
		ty.size = 1;

		return ty;
	}
	case TK_TY_U8: {
		Type ty{};
		ty.kind = TY_U8;
		ty.name = "$internal$_u8";
		ty.size = 1;

		return ty;
	}
	case TK_TY_I8: {
		Type ty{};
		ty.kind = TY_I8;
		ty.name = "$internal$_i8";
		ty.size = 1;

		return ty;
	}
	case TK_TY_U16: {
		Type ty{};
		ty.kind = TY_U16;
		ty.name = "$internal$_u16";
		ty.size = 2;

		return ty;
	}
	case TK_TY_I16: {
		Type ty{};
		ty.kind = TY_I16;
		ty.name = "$internal$_i16";
		ty.size = 2;

		return ty;
	}
	case TK_TY_U32: {
		Type ty{};
		ty.kind = TY_U32;
		ty.name = "$internal$_u32";
		ty.size = 4;

		return ty;
	}
	case TK_TY_I32: {
		Type ty{};
		ty.kind = TY_I32;
		ty.name = "$internal$_i32";
		ty.size = 4;

		return ty;
	}
	case TK_TY_U64: {
		Type ty{};
		ty.kind = TY_U64;
		ty.name = "$internal$_u64";
		ty.size = 8;

		return ty;
	}
	case TK_TY_I64: {
		Type ty{};
		ty.kind = TY_I64;
		ty.name = "$internal$_i64";
		ty.size = 8;

		return ty;
	}
	case TK_TY_F32: {
		Type ty{};
		ty.kind = TY_F32;
		ty.name = "$internal$_f32";
		ty.size = 4;

		return ty;
	}
	case TK_TY_F64: {
		Type ty{};
		ty.kind = TY_F64;
		ty.name = "$internal$_f64";
		ty.size = 8;

		return ty;
	}
	case TK_TY_RAWPTR: {
		Type ty{};
		ty.kind = TY_RAWPTR;
		ty.name = "$internal$_rawptr";
		ty.size = -1;

		return ty;
	}
	case TK_TY_STR: {
		Type ty{};
		ty.kind = TY_STR;
		ty.name = "$internal$_str";
		ty.size = -1;

		return ty;
	}
	default:
		Compiler::panic(tk.span, "Syntax Error! Unexpected token in typename: %s\n", tk_as_str(tk.kind));
	}
}

TypeID Parser::register_type(Type& type)
{
	if (m_root_module.type_id_map.find(type.name) != m_root_module.type_id_map.end())
		return m_root_module.type_id_map[type.name];

	m_root_module.types.push_back(type);
	m_root_module.type_id_map[type.name] = m_root_module.types.size() - 1;
	return m_root_module.types.size() - 1;
}

std::vector<StructMember> Parser::parse_struct_members()
{
	std::vector<StructMember> members;

	eat_next_specific(TK_L_CURLY);

	for (;;) {
		Token name = current();
		if (name.kind == TK_EOL) {
			m_idx++;
			continue;
		}

		if (name.kind != TK_IDENT)
			Compiler::panic(name.span, "Syntax Error! Expected struct member name, got: %s", tk_as_str(name.kind));

		eat_next_specific(TK_COLON);

		Type raw_type = parse_raw_type();
		TypeID type = register_type(raw_type);

		eat_next_specific(TK_SEMICOLON);

		members.push_back(StructMember {
			name.str,
			type,
		});

		Token end = next();
		if (end.kind == TK_R_CURLY)
			break;
	}

	return members;
}

std::vector<ProcParameter> Parser::parse_proc_decl_param_list()
{
	std::vector<ProcParameter> params;

	Token curr = current();
	if (curr.kind != TK_L_PAREN)
		Compiler::panic(curr.span, "Syntax Error! Expected '(', got: %s\n", tk_as_str(curr.kind));

	Token tk = next();
	for (;;) {
		Token name = current();
		if (name.kind != TK_IDENT)
			Compiler::panic(name.span, "Syntax Error! Expected identifier in parameter list, got: %s\n", tk_as_str(name.kind));

		eat_next_specific(TK_COLON);

		Type raw_type = parse_raw_type();
		TypeID type = register_type(raw_type);

		ProcParameter param{ };
		param.name = name.str;
		param.type = type;
		// TODO: Parse default parameter values once we figure out a good way to express
		//       the acceptance of the default value. (Perhaps passing '_' to indicate
		//       that you want to use the default, rather that forcing you to make it the
		//       last parameter in the funciton.)
		param.default_value = nullptr;

		params.push_back(param);

		Token comma = next();
		if (comma.kind == TK_COMMA) {
			m_idx++;
			continue;
		} else if (comma.kind == TK_R_PAREN) {
			break;
		} else {
			Compiler::panic(comma.span, "Syntax Error! Expected ',' or ')', got: %s", tk_as_str(comma.kind));
		}
	}

	return params;
}

Block Parser::parse_stmnt_block()
{
	std::vector<Stmnt*> stmnts;

	eat_whitespace();

	eat_current_specific(TK_L_CURLY);

	Token tk = current();
	while (tk.kind != TK_R_CURLY) {
		Stmnt* stmnt = parse_statement();
		if (stmnt) // VarDecls are stored elsewhere, so we dont need to worry about adding them
			stmnts.push_back(stmnt);
		tk = current();
	}

	return Block{ std::move(stmnts) };
}

Token Parser::current()
{
	return peek(0);
}

Token Parser::next()
{
	m_idx++;
	return current();
}

void Parser::eat_next_specific(TokenKind kind)
{
	Token tk = next();
	m_idx++;
	if (tk.kind != kind)
		Compiler::panic(tk.span, "Syntax Error! Expected: %s, got %s", tk_as_str(kind), tk_as_str(tk.kind));
}

void Parser::eat_current_specific(TokenKind kind)
{
	Token tk = current();
	m_idx++;
	if (tk.kind != kind)
		Compiler::panic(tk.span, "Syntax Error! Expected: %s, got %s", tk_as_str(kind), tk_as_str(tk.kind));
}

void Parser::eat_whitespace()
{
	Token tk = current();
	while (tk.kind == TK_EOL) {
		tk = next();
	}
}

Token Parser::peek(int64_t offset)
{
	assert(m_idx + offset < m_token_stream.size());

	return m_token_stream[m_idx + offset];
}
