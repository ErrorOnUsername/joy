" Vim syntax file
" Language: Joy
" Lastest Revision: 12-10-2023

if exists("b:current_syntax")
	finish
endif

let s:cpo_save = &cpo
set cpo&vim

"
" Keywords
"
syn keyword j_conditionals    if else switch
syn keyword j_loops           while for loop
syn keyword j_ctrl_flow       return break continue
syn keyword j_boolean         true false
syn keyword j_keyword         decl let mut as in is
syn keyword j_type            bool char u8 i8 u16 i16 u32 i32 u64 i64 uint int f32 f64 string cstring rawptr
syn keyword j_complex_type    struct enum union fn
syn keyword j_todo            contained NOTE TODO FIXME BUG

"
" Numbers
"
syn match j_dec_number display "\v<\d%(_?\d)*"
syn match j_bin_number display "\v<0b[01]%(_?[01])*"
syn match j_oct_number display "\v<0o\o%(_?\o)*"
syn match j_hex_number display "\v<0x\x%(_?\x)*"

hi def link j_dec_number      j_number
hi def link j_bin_number      j_number
hi def link j_oct_number      j_number
hi def link j_hex_number      j_number

"
" String
"
syn region j_string_literal matchgroup=j_string_delim start=+"+ skip=+\\\\\|\\"+ end=+"+ oneline contains=j_escape
syn region j_char_literal   matchgroup=j_char_delim start=+'+ skip=+\\\\\|\\'+ end=+'+ oneline contains=j_escape
syn match  j_escape         display contained /\\./

"
" Functions
"
syn match j_proc_call /\w\+\s*(/me=e-1,he=e-1
hi def link j_proc_call       j_proc

"
" Types
"
syn match j_const_decl /decl\s\+\w\+\s\+[:=]/lc=4,he=e-1

hi def link j_const_decl       j_type

"
" Comments
"
syn region j_line_comment  start="//"  end="$"   contains=j_todo
syn region j_block_comment start="/\*" end="\*/" contains=j_todo,j_block_comment

hi def link j_line_comment    j_comment
hi def link j_block_comment   j_comment

"
" Linking to vim highlight types
"
hi def link j_conditionals    Conditional
hi def link j_loops           Repeat
hi def link j_ctrl_flow       Special
hi def link j_boolean         Boolean
hi def link j_keyword         Keyword
hi def link j_directives      Macro
hi def link j_type            Type
hi def link j_complex_type    Keyword
hi def link j_number          Number
hi def link j_comment         Comment
hi def link j_proc            Function
hi def link j_string_literal  String
hi def link j_string_delim    String
hi def link j_char_literal    String
hi def link j_char_delim      String

let b:current_syntax = "joy"

let &cpo = s:cpo_save
unlet s:cpo_save

