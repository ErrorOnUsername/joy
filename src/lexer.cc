#include "lexer.hh"
#include <cassert>
#include <cmath>
#include <string>
#include <iostream>

#include "compiler.hh"

#define TK_WITH_B_FORM(kind) \
{ \
	Token tk(m_file_id, kind, m_idx, m_line); \
	m_idx++; \
	tk.span.end_idx = m_idx; \
	return tk; \
}

#define TK_WITH_BX_FORM(bare_kind, extra_ch, extra_kind) \
{ \
	Token tk(m_file_id, bare_kind, m_idx, m_line); \
	m_idx++; \
	if (current() == extra_ch) { \
		tk.kind = extra_kind; \
		m_idx++; \
	} \
	tk.span.end_idx = m_idx; \
	return tk; \
}

#define TK_WITH_BO_FORM(bare_kind, extra_ch, extra_kind, tail_ch, tail_kind) \
{ \
	Token tk(m_file_id, bare_kind, m_idx, m_line); \
	m_idx++; \
	if (current() == extra_ch) { \
		tk.kind = extra_kind; \
		m_idx++; \
	} else if (current() == tail_ch) { \
		tk.kind = tail_kind; \
		m_idx++; \
	} \
	tk.span.end_idx = m_idx; \
	return tk; \
}

Lexer::Lexer(std::string const& filepath)
	: m_file_id()
	, m_file_data()
	, m_idx(0)
	, m_line(1)
{
	m_file_id = Compiler::open_file(filepath);
	m_file_data = Compiler::file_data(m_file_id);
}

Token Lexer::next_tk()
{
	while (!at_eof()) {
		switch (current()) {
			case '\n': {
				Token tk(m_file_id, TK_EOL, m_idx, m_line);
				m_idx++;
				m_line++;
				tk.span.end_idx = m_idx;

				return tk;
			}
			case ' ':
			case '\t':
			case '\r':
				m_idx++;
				break;

			case '\'': return tokenize_char_literal();
			case '"': return tokenize_string_literal();

			case '[': TK_WITH_B_FORM(TK_L_SQUARE);
			case ']': TK_WITH_B_FORM(TK_R_SQUARE);
			case '{': TK_WITH_B_FORM(TK_L_CURLY);
			case '}': TK_WITH_B_FORM(TK_R_CURLY);
			case '(': TK_WITH_B_FORM(TK_L_PAREN);
			case ')': TK_WITH_B_FORM(TK_R_PAREN);
			case '!': TK_WITH_BX_FORM(TK_BANG, '=', TK_NEQ);
			case '$': TK_WITH_B_FORM(TK_DOLLAR);
			case '%': TK_WITH_BX_FORM(TK_PERCENT, '=', TK_PERCENT_ASSIGN);
			case '^': TK_WITH_BO_FORM(TK_CARET, '^', TK_XOR, '=', TK_CARET_ASSIGN);
			case '&': TK_WITH_BO_FORM(TK_AMPERSAND, '&', TK_AND, '=', TK_AMPERSAND_ASSIGN);
			case '*': TK_WITH_BX_FORM(TK_STAR, '=', TK_STAR_ASSIGN);
			case '-': TK_WITH_BO_FORM(TK_MINUS, '-', TK_MINUS_MINUS, '=', TK_MINUS_ASSIGN);
			case '+': TK_WITH_BO_FORM(TK_PLUS, '+', TK_PLUS_PLUS, '=', TK_PLUS_ASSIGN);
			case '=': TK_WITH_BO_FORM(TK_ASSIGN, '=', TK_EQ, '>', TK_THICC_ARROW);
			case '|': TK_WITH_BO_FORM(TK_PIPE, '|', TK_OR, '=', TK_PIPE_ASSIGN);
			case ';': TK_WITH_B_FORM(TK_SEMICOLON);
			case ':': TK_WITH_BO_FORM(TK_COLON, ':', TK_DOUBLE_COLON, '=', TK_COLON_ASSIGN);
			case ',': TK_WITH_B_FORM(TK_COMMA);
			case '.': TK_WITH_BX_FORM(TK_DOT, '.', TK_DOT_DOT);
			case '<': TK_WITH_BX_FORM(TK_L_ANGLE, '=', TK_LEQ);
			case '>': TK_WITH_BX_FORM(TK_R_ANGLE, '=', TK_GEQ);
			case '/': {
				if (peek() == '/') {
					while (current() != '\n' && !at_eof()) {
						m_idx++;
					}

					continue;
				} else if (peek() == '*') {
					while (!at_eof()) {
						if (current() == '/' && peek(-1) == '*') break;
						if (current() == '\n') m_line++;
						m_idx++;
					}

					continue;
				} else {
					Token tk(m_file_id, TK_SLASH, m_idx, m_line);
					m_idx++;
					if (current() == '=') {
						tk.kind = TK_SLASH_ASSIGN;
						m_idx++;
					}
					tk.span.end_idx = m_idx;
					return tk;
				}

				break;
			}
			case '0':
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
			case '8':
			case '9': return tokenize_number();
			case '#': return tokenize_directive();
			default: return tokenize_ident();
		}
	}

	return Token(m_file_id, TK_EOF, -1, -1);
}

static bool is_valid_number_char(char c)
{
	return (c >= '0' && c <= '9') ||
	       (c >= 'A' && c <= 'F') ||
	       (c >= 'a' && c <= 'f');
}

static uint8_t ch_to_val(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	else if (c >= 'A' && c <= 'F')
		return (c + 10) - 'A';
	else if (c >= 'a' && c <= 'f')
		return (c + 10) - 'a';

	return 0;
}

Token Lexer::tokenize_number()
{
	Token tk(m_file_id, TK_NUMBER, m_idx, m_line);

	uint64_t i_num = 0;
	double f_num = 0.0;

	uint64_t decimal_lead = 0;
	uint64_t fractional_tail = 0;
	uint64_t e_power = 0;
	int radix = 10;
	bool is_float = false;

	char c;
	while (!at_eof()) {
		c = current();

		if (c == '.' || c == 'e' || c == 'E') {
			assert(radix == 10);
			is_float = true;
			break;
		} else if (!is_valid_number_char(c)) {
			break;
		}
		uint64_t val = ch_to_val(c);
		assert(val < radix);

		decimal_lead *= radix;
		decimal_lead += val;

		m_idx++;
	}

	i_num = decimal_lead;
	f_num = (double)decimal_lead;

	if (c == '.') {
		assert(radix == 10);
		if (is_valid_number_char(peek())) {
			m_idx++;
			is_float = true;

			int place = 1;
			char c = current();
			while (!at_eof() && is_valid_number_char(c)) {
				if (c == 'e' || c == 'E') break;

				uint64_t val = ch_to_val(c);
				assert(val < radix);

				fractional_tail *= radix;
				fractional_tail += val;

				place *= 10;
				m_idx++;
				c = current();
			}

			f_num += ((double)fractional_tail / place);
		}
	}

	c = current();
	if (c == 'e' || c == 'E') {
		assert(radix == 10);
		m_idx++;
		is_float = true;

		char c = current();
		while (!at_eof() && is_valid_number_char(c)) {
			uint64_t val = ch_to_val(c);
			assert(val < radix);

			e_power *= radix;
			e_power += val;

			m_idx++;
			c = current();
		}
		double f = pow(10.0, (double)e_power);
		f_num *= pow(10.0, (double)e_power);
	}

	tk.span.end_idx = m_idx;

	if (is_float) {
		tk.number.kind = NK_FLOAT;
		tk.number.floating_point = f_num;
	} else {
		tk.number.kind = NK_UINT;
		tk.number.uint = i_num;
	}

	return tk;
}

bool is_valid_ident_char(char c)
{
	return (c >= 'a' && c <= 'z') ||
	       (c >= 'A' && c <= 'Z') ||
	       is_valid_number_char(c) ||
	       (c == '_');
}

Token Lexer::tokenize_ident()
{
	Token tk(m_file_id, TK_IDENT, m_idx, m_line);
	std::string str;
	char c = current();

	assert(is_valid_ident_char(c));

	while (!at_eof() && is_valid_ident_char(c)) {
		str.push_back(c);
		m_idx++;
		c = current();
	}

	if (str == "true")
		tk.kind = TK_BOOL_T;
	else if (str == "false")
		tk.kind = TK_BOOL_F;
	else if (str == "decl")
		tk.kind = TK_KW_DECL;
	else if (str == "let")
		tk.kind = TK_KW_LET;
	else if (str == "if")
		tk.kind = TK_KW_IF;
	else if (str == "else")
		tk.kind = TK_KW_ELSE;
	else if (str == "for")
		tk.kind = TK_KW_FOR;
	else if (str == "while")
		tk.kind = TK_KW_WHILE;
	else if (str == "loop")
		tk.kind = TK_KW_LOOP;
	else if (str == "continue")
		tk.kind = TK_KW_CONTINUE;
	else if (str == "break")
		tk.kind = TK_KW_BREAK;
	else if (str == "return")
		tk.kind = TK_KW_RETURN;
	else if (str == "in")
		tk.kind = TK_KW_IN;
	else if (str == "as")
		tk.kind = TK_KW_AS;
	else if (str == "struct")
		tk.kind = TK_KW_STRUCT;
	else if (str == "enum")
		tk.kind = TK_KW_ENUM;
	else if (str == "union")
		tk.kind = TK_KW_UNION;
	else if (str == "nothing")
		tk.kind = TK_TY_NOTHING;
	else if (str == "char")
		tk.kind = TK_TY_CHAR;
	else if (str == "bool")
		tk.kind = TK_TY_BOOL;
	else if (str == "u8")
		tk.kind = TK_TY_U8;
	else if (str == "i8")
		tk.kind = TK_TY_I8;
	else if (str == "u16")
		tk.kind = TK_TY_U16;
	else if (str == "i16")
		tk.kind = TK_TY_I16;
	else if (str == "u32")
		tk.kind = TK_TY_U32;
	else if (str == "i32")
		tk.kind = TK_TY_I32;
	else if (str == "u64")
		tk.kind = TK_TY_U64;
	else if (str == "i64")
		tk.kind = TK_TY_I64;
	else if (str == "f32")
		tk.kind = TK_TY_F32;
	else if (str == "f64")
		tk.kind = TK_TY_F64;
	else if (str == "rawptr")
		tk.kind = TK_TY_RAWPTR;
	else if (str == "string")
		tk.kind = TK_TY_STR;
	else
		tk.str = std::move(str);

	tk.span.end_idx = m_idx;

	return tk;
}

Token Lexer::tokenize_directive()
{
	Token tk(m_file_id, TK_INVAL, m_idx, m_line);
	m_idx++;

	std::string str;

	char c = current();
	while (!at_eof() && is_valid_ident_char(c)) {
		str.push_back(c);
		m_idx++;
		c = current();
	}

	tk.span.end_idx = m_idx;

	if (str == "load")
		tk.kind = TK_CD_LOAD;
	else
		Compiler::panic(tk.span, "compile-time directive: \"%s\" is unknown", str.c_str());

	return tk;
}

Token Lexer::tokenize_char_literal()
{
	Token tk(m_file_id, TK_CHAR_LIT, m_idx, m_line);
	m_idx++;

	char c = 0;

	if (current() == '\\') {
		if (peek() == 'x' || peek() == 'b') {
			tk.span.end_idx = m_idx + 1;
			Compiler::panic(tk.span, "Add support for number literal escape chars");
		}

		char nc = peek();

		switch (nc) {
			case 'r':
				c = '\r';
				m_idx += 2;
				break;
			case 'n':
				c = '\n';
				m_idx += 2;
				break;
			case 't':
				c = '\t';
				m_idx += 2;
				break;
			case 'v':
				c = '\v';
				m_idx += 2;
				break;
			case '\'':
				c = '\'';
				m_idx += 2;
				break;
			default:
				c = peek();
				m_idx += 2;
		}
	} else {
		c = current();
		m_idx++;
	}

	assert(current() == '\'');
	m_idx++;

	tk.str.push_back(c);
	tk.span.end_idx = m_idx;

	return tk;
}

Token Lexer::tokenize_string_literal()
{
	Token tk(m_file_id, TK_STR_LIT, m_idx, m_line);
	std::string str;

	m_idx++;

	char c = current();
	while (!at_eof() && c != '"') {
		if (c == '\\') {
			if (peek() == 'x' || peek() == 'b') {
				tk.span.end_idx = m_idx + 2;
				Compiler::panic(tk.span, "Add support for number literal escape chars");
			}

			char nc = peek();

			switch (nc) {
			case 'r':
				str.push_back('\r');
				m_idx += 2;
				break;
			case 'n':
				str.push_back('\n');
				m_idx += 2;
				break;
			case 't':
				str.push_back('\t');
				m_idx += 2;
				break;
			case 'v':
				str.push_back('\v');
				m_idx += 2;
				break;
			case '"':
				str.push_back('"');
				m_idx += 2;
				break;
			default:
				str.push_back('\\');
				m_idx++;
			}
		} else if (c == '\n') {
			tk.span.end_idx = m_idx;
			Compiler::panic(tk.span, "Unterminated string literal");
		}

		str.push_back(c);

		m_idx++;
		c = current();
	}
	if (at_eof()) {
		tk.span.end_idx = m_idx;
		Compiler::panic(tk.span, "Unterminated string literal");
	}

	assert(c == '"');
	m_idx++;

	tk.str = std::move(str);
	tk.span.end_idx = m_idx;
	return tk;
}

char Lexer::current()
{
	return peek(0);
}

char Lexer::peek(int64_t offset)
{
	if ((size_t)(m_idx + offset) >= m_file_data.size()) {
		return 0;
	}

	return m_file_data[m_idx + offset];
}

bool Lexer::at_eof()
{
	return (size_t)m_idx >= m_file_data.size();
}
