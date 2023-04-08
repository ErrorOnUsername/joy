#include "typechecker.hh"

#include "compiler.hh"
#include "profiling.hh"


static void import_data_from_child_module( Module* module, Module* sub_module )
{
	TIME_PROC();

	// TODO: Globals, enums, and unions

	for ( auto& struct_decl : sub_module->structs )
	{
		TIME_SCOPE( "Import Structs" );

		if ( module->type_registry.find( struct_decl.name ) != module->type_registry.cend() )
			Compiler::panic( struct_decl.span, "Type '%s' is already defined in direct parent module: '%s'", struct_decl.name.c_str(), "DEV NEEDS TO ADD THIS, SORRY FOR THE BAD ERROR" );

		module->type_registry[struct_decl.name] = TY_STRUCT;
	}

	for ( auto& proc_decl : sub_module->procs )
	{
		TIME_SCOPE( "Import Procedures" );

		if ( module->proc_registry.find( proc_decl.name ) != module->proc_registry.cend() )
			Compiler::panic( proc_decl.span, "Procedure '%s' is already defined in child module: '%s'", proc_decl.name.c_str(), "DEV NEEDS TO ADD THIS, SORRY FOR THE BAD ERROR" );

		module->proc_registry[proc_decl.name] = &proc_decl;
	}
}


static void typecheck_block( Module* module, Block& block );


void typecheck_module( Module* module )
{
	TIME_PROC();

	for ( Module* module_dep : module->imports )
	{
		TIME_SCOPE( "Typecheck Child Modules" );
		typecheck_module( module_dep );

		import_data_from_child_module( module, module_dep );
	}

	for ( StructDeclStmnt& struct_decl : module->structs )
	{
		TIME_SCOPE( "Typecheck Structs" );

		for ( StructMember& member : struct_decl.members )
		{
			if ( member.type.kind != TY_UNKNOWN ) continue;

			if ( module->type_registry.find( member.type.name ) == module->type_registry.cend() )
				Compiler::panic( member.type.span, "Unknown typename: '%s'\n", member.type.name.c_str() );

			// FIXME: This isn't sufficient checking. Since some member's
			//        member could be the same type as the current.
			if ( member.type.kind != TY_PTR && member.type.name == struct_decl.name )
				Compiler::panic( member.type.span, "To have a sub-member the same type as the parent, it must be indirected. Consider making it a pointer." );

			member.type.kind = module->type_registry.at( member.type.name );
		}
	}

	// TODO: check enums and unions

	// TODO: check constants and globals

	for ( ProcDeclStmnt& proc_decl : module->procs )
	{
		TIME_SCOPE( "Pre-load Local Procedures" );

		// Pre-initialize the proc_registry with module-local procedures
		if ( module->proc_registry.find( proc_decl.name ) != module->proc_registry.cend() )
			Compiler::panic( proc_decl.span, "This procedure has already been defined" );

		module->proc_registry[proc_decl.name] = &proc_decl;
	}

	for ( ProcDeclStmnt& proc_decl : module->procs )
	{
		TIME_SCOPE( "Typecheck Local Procedures" );

		for ( auto& param : proc_decl.params )
		{
			if ( param.type.kind != TY_UNKNOWN ) continue;

			if ( module->type_registry.find( param.type.name ) == module->type_registry.cend() )
				Compiler::panic( param.type.span, "Unknown typename: '%s'", param.type.name.c_str() );

			param.type.kind = module->type_registry.at( param.type.name );
		}

		if ( proc_decl.return_type.kind == TY_UNKNOWN )
		{
			if ( module->type_registry.find( proc_decl.return_type.name ) == module->type_registry.cend() )
				Compiler::panic( proc_decl.return_type.span, "Unknown typename: '%s'", proc_decl.return_type.name.c_str() );

			proc_decl.return_type.kind = module->type_registry.at( proc_decl.return_type.name );
		}

		typecheck_block( module, proc_decl.body );
	}
}


static void typecheck_expr( Module* module, Expr* var_decl );
static void typecheck_var_decl( Module* module, VarDeclStmnt* var_decl );

static bool are_types_equal( Type* type_0, Type* type_1 );
static bool can_perform_binop( BinOpKind kind, Expr* lhs, Expr* rhs );
static bool can_perform_uop( UnaryOpKind kind, Expr* operand );


static void typecheck_block( Module* module, Block& block )
{
	for ( size_t i = 0; i < block.stmnts.size(); i++ )
	{
		Stmnt* stmnt = block.stmnts[i];

		switch ( stmnt->kind )
		{
			case STMNT_CONST_DECL:
				break;
			case STMNT_STRUCT_DECL:
				break;
			case STMNT_ENUM_DECL:
				break;
			case STMNT_PROC_DECL:
				break;
			case STMNT_VAR_DECL:
				typecheck_var_decl( module, (VarDeclStmnt*)stmnt );
				break;
			case STMNT_IF:
				break;
			case STMNT_FOR:
				break;
			case STMNT_WHILE:
				break;
			case STMNT_LOOP:
				break;
			case STMNT_CONTINUE:
				break;
			case STMNT_BREAK:
				break;
			case STMNT_RETURN:
				break;
			case STMNT_BLOCK:
				break;
			case STMNT_EXPR:
				break;
			default: Compiler::panic( stmnt->span, "wha? %zu", (size_t)stmnt->kind ); TODO();
		}
	}
}


static void typecheck_var_decl( Module* module, VarDeclStmnt* var_decl )
{
	if ( var_decl->type.kind == TY_UNKNOWN )
	{
		if ( module->type_registry.find( var_decl->type.name ) == module->type_registry.cend() )
			Compiler::panic( var_decl->type.span, "Unknown typename: '%s'", var_decl->type.name.c_str() );

		var_decl->type.kind = module->type_registry.at( var_decl->type.name );
	}

	typecheck_expr( module, var_decl->default_value );

	if ( var_decl->type.kind == TY_AUTO )
		var_decl->type.kind = var_decl->default_value->result_ty.kind;

	if ( var_decl->type.kind == TY_AUTO_INT )
		var_decl->type.kind = TY_I32; // TODO: ISIZE
	else if ( var_decl->type.kind == TY_AUTO_FLOAT )
		var_decl->type.kind = TY_F32;

	if ( !are_types_equal( &var_decl->type, &var_decl->default_value->result_ty ) )
		Compiler::panic( var_decl->default_value->result_ty.span, "The resulting type of this expression is '%s', which is incongruent with the variable declaration type '%s'", var_decl->default_value->result_ty.name.c_str(), var_decl->type.name.c_str() );
}


static void typecheck_expr( Module* module, Expr* expr )
{
	switch( expr->kind )
	{
		case EXPR_BOOL:
		{
			expr->result_ty.kind = TY_BOOL;
			break;
		}
		case EXPR_NUMBER:
		{
			ConstNumberExpr* num_expr = (ConstNumberExpr*)expr;
			Number& number = num_expr->num;

			switch ( number.kind )
			{
				case NK_INT:
					num_expr->result_ty.kind = TY_AUTO_INT;
					break;
				case NK_FLOAT:
					num_expr->result_ty.kind = TY_AUTO_FLOAT;
					break;
			}

			break;
		}
		case EXPR_STRING:
		{
			expr->result_ty.kind = TY_AUTO_STRING;
			break;
		}
		case EXPR_CHAR:
		{
			expr->result_ty.kind = TY_CHAR;
			break;
		}
		case EXPR_VAR:
		{
			VarExpr* var_expr = (VarExpr*)expr;

			VarID id = var_expr->var_id;
			if ( id == -1 )
			{
				// If the variable wasn't found, then we should look for it
				// in the global scope, since it might've been defined
				// out-of-order.
				Scope& module_global_scope = module->scopes[0];
				if ( module_global_scope.vars_id_map.find( var_expr->name ) != module_global_scope.vars_id_map.cend() )
				{
					id = module_global_scope.vars_id_map.at( var_expr->name );
				}
				else
				{
					Compiler::panic( var_expr->span, "Undeclared identifier '%s'\n", var_expr->name.c_str() );
				}
			}

			var_expr->result_ty = module->vars[id].type;

			break;
		}
		case EXPR_RANGE:
		{
			RangeExpr* range_expr = (RangeExpr*)expr;

			typecheck_expr( module, range_expr->lhs );
			typecheck_expr( module, range_expr->rhs );

			if ( !are_types_equal( &range_expr->lhs->result_ty, &range_expr->rhs->result_ty ) )
				Compiler::panic( range_expr->span, "Range bounds are of incongruent types" );

			break;
		}
		case EXPR_PROC_CALL:
		{
			ProcCallExpr* call_expr = (ProcCallExpr*)expr;
			if ( module->proc_registry.find( call_expr->name ) == module->proc_registry.cend() )
				Compiler::panic( call_expr->span, "Undefined procedure: '%s'", call_expr->name.c_str() );

			ProcDeclStmnt* decl = module->proc_registry.at( call_expr->name );

			if ( call_expr->params.size() != decl->params.size() )
				Compiler::panic( call_expr->span, "Expected %zu arguments, got %zu", decl->params.size(), call_expr->params.size() );

			for ( size_t i = 0; i < call_expr->params.size(); i++ )
			{
				Expr* param = call_expr->params[i];

				typecheck_expr( module, param );

				if ( !are_types_equal( &param->result_ty, &decl->params[i].type ) )
					Compiler::panic( param->span, "expected argument of type '%s', got type '%s'", param->result_ty.name.c_str(), decl->params[i].type.name.c_str() );
			}

			call_expr->result_ty = decl->return_type;

			break;
		}
		case EXPR_BIN_OP:
		{
			BinOpExpr* binop_expr = (BinOpExpr*)expr;

			typecheck_expr( module, binop_expr->lhs );
			typecheck_expr( module, binop_expr->rhs );

			if ( !can_perform_binop( binop_expr->op_kind, binop_expr->lhs, binop_expr->rhs ) )
				Compiler::panic( binop_expr->span, "Cannot perform binary operation" );

			break;
		}
		case EXPR_UNARY_OP:
		{
			UnaryOpExpr* uop_expr = (UnaryOpExpr*)expr;

			typecheck_expr( module, uop_expr->operand );

			if ( !can_perform_uop( uop_expr->op_kind, uop_expr->operand ) )
				Compiler::panic( uop_expr->span, "Cannot perform unary operation on operand" );

			break;
		}
	}
}


static bool is_primitive_number( TypeKind kind )
{
	return ( kind == TY_U8 )
	    || ( kind == TY_I8 )
	    || ( kind == TY_U16 )
	    || ( kind == TY_I16 )
	    || ( kind == TY_U32 )
	    || ( kind == TY_I32 )
	    || ( kind == TY_U64 )
	    || ( kind == TY_I32 )
	    || ( kind == TY_F32 )
	    || ( kind == TY_F64 );

}


static bool are_types_equal( Type* type_0, Type* type_1 )
{
	if ( type_0->kind != type_1->kind ) return false;

	if ( type_0->kind == TY_STRUCT || type_0->kind == TY_ENUM || type_0->kind == TY_UNION )
		return type_0->name == type_1->name;

	return false;
}


static bool can_perform_binop( BinOpKind kind, Expr* lhs, Expr* rhs )
{
	// TODO: Coersion...

	if ( lhs->result_ty.kind != rhs->result_ty.kind )
		return false;

	TypeKind ty_kind = lhs->result_ty.kind;

	switch ( kind )
	{
		case B_OP_MEMBER_ACCESS: return ty_kind == TY_STRUCT || ty_kind == TY_ENUM || ty_kind == TY_UNION;
		case B_OP_ADD:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_SUB:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_MUL:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_DIV:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_MOD:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_L_AND:         return ty_kind == TY_BOOL;
		case B_OP_B_AND:         return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_L_OR:          return ty_kind == TY_BOOL;
		case B_OP_B_OR:          return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_L_XOR:         return ty_kind == TY_BOOL;
		case B_OP_B_XOR:         return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_EQ:            return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR || ty_kind == TY_BOOL;
		case B_OP_NEQ:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR || ty_kind == TY_BOOL;
		case B_OP_LT:            return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_LEQ:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_GT:            return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_GEQ:           return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_ADD_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_SUB_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_MUL_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_DIV_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_MOD_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_AND_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_OR_ASSIGN:     return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_XOR_ASSIGN:    return is_primitive_number( ty_kind ) || ty_kind == TY_RAWPTR;
		case B_OP_ASSIGN:        return ty_kind != TY_UNKNOWN;
		default:                 return false;
	}

	return false;
}


static bool can_perform_uop( UnaryOpKind kind, Expr* operand )
{
	TypeKind ty_kind = operand->result_ty.kind;

	switch ( kind )
	{
		case U_OP_NEG:      return is_primitive_number( ty_kind );
		case U_OP_PRE_INC:  return is_primitive_number( ty_kind ) && !( ty_kind == TY_F32 || ty_kind == TY_F64 );
		case U_OP_PRE_DEC:  return is_primitive_number( ty_kind ) && !( ty_kind == TY_F32 || ty_kind == TY_F64 );
		case U_OP_POST_INC: return is_primitive_number( ty_kind ) && !( ty_kind == TY_F32 || ty_kind == TY_F64 );
		case U_OP_POST_DEC: return is_primitive_number( ty_kind ) && !( ty_kind == TY_F32 || ty_kind == TY_F64 );
		case U_OP_ADDR_OF:  return ty_kind != TY_UNKNOWN;
		case U_OP_DEREF:    return ty_kind == TY_PTR;
		case U_OP_L_NOT:    return ty_kind == TY_BOOL;
		case U_OP_CAST:     return ty_kind != TY_UNKNOWN;
		default:            return false;
	}

	return false;
}
