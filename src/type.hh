#pragma once
#include <string>

enum TypeKind {
	TY_NOTHING,
	TY_BOOL,
	TY_CHAR,
	TY_U8,
	TY_I8,
	TY_U16,
	TY_I16,
	TY_U32,
	TY_I32,
	TY_U64,
	TY_I64,
	TY_F32,
	TY_F64,
	TY_PTR,
	TY_RAWPTR,
	TY_STR,
	TY_CSTR,
	TY_ARRAY,
	TY_STRUCT,
	TY_ENUM,
	TY_UNKNOWN,
};

using TypeID = int64_t;

struct Expr;

struct Type {
	TypeKind kind = TY_UNKNOWN;
	std::string name;

	union {
		Expr* size_expr;
		int64_t size;
	};

	union {
		size_t str_len;
		size_t struct_id;
		size_t enum_id;
		TypeID underlying;
	};
};
