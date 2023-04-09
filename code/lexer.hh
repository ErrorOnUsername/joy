#pragma once

#include "file_manager.hh"
#include "token.hh"

Token Lexer_GetNextToken( FileLexInfo& file_lex_info );
