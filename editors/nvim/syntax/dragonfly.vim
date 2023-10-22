" Vim syntax file
" Language: Dragonfly
" Lastest Revision: 10-22-2023

if exists("b:current_syntax")
	finish
endif

let s:cpo_save = &cpo
set cpo&vim

"
" Keywords
"
syn keyword df_conditionals    if else switch
syn keyword df_loops           while for loop
syn keyword df_ctrl_flow       return break continue
syn keyword df_boolean         true false
syn keyword df_keyword         decl let as in is
syn keyword df_type            bool char u8 i8 u16 i16 u32 i32 u64 i64 usize isize f32 f64 string cstring rawptr
syn keyword df_complex_type    struct enum union
syn keyword df_todo            contained NOTE TODO FIXME BUG

"
" Numbers
"
syn match df_dec_number display "\v<\d%('?\d)*"
syn match df_bin_number display "\v<0b[01]%('?[01])*"
syn match df_oct_number display "\v<0o\o%('?\o)*"
syn match df_hex_number display "\v<0x\x%('?\x)*"

hi def link df_dec_number      df_number
hi def link df_bin_number      df_number
hi def link df_oct_number      df_number
hi def link df_hex_number      df_number

"
" String
"
syn region df_string_literal matchgroup=df_string_delim start=+"+ skip=+\\\\\|\\"+ end=+"+ oneline contains=df_escape
syn region df_char_literal   matchgroup=df_char_delim start=+'+ skip=+\\\\\|\\'+ end=+'+ oneline contains=df_escape
syn match  df_escape         display contained /\\./

"
" Operators
"
syn match df_simple_op      display "\V\[-+/*=^&?|!><%~:]"
syn match df_thicc_arrow_op display "\V=>"
syn match df_thin_arrow_op  display "\V->"
syn match df_range_op       display "\V.."

hi def link df_simple_op       df_operator
hi def link df_thicc_arrow_op  df_operator
hi def link df_thin_arrow_op   df_operator
hi def link df_range_arrow_op  df_operator

"
" Compile-Time Directives
"
syn match df_directive /#\w\+\_[[:space:]\r\n]/

hi def link df_directive       df_directives

"
" Functions
"
syn match df_proc_decl /decl\s\+\w\+\s\+:\s\+(/lc=4,he=e-4
syn match df_proc_call /\w\+\s*(/me=e-1,he=e-1

hi def link df_proc_decl       df_proc
hi def link df_proc_call       df_proc

"
" Types
"
syn match df_struct_decl /decl\s\+\w\+\s\+:\s\+struct\+/lc=4,me=e-8
syn match df_enum_decl   /decl\s\+\w\+\s\+:\s\+enum\+/lc=4,me=e-6

hi def link df_struct_decl     df_type
hi def link df_enum_decl       df_type

"
" Comments
"
syn region df_line_comment  start="//"  end="$"   contains=df_todo
syn region df_block_comment start="/\*" end="\*/" contains=df_todo,df_block_comment

hi def link df_line_comment    df_comment
hi def link df_block_comment   df_comment

"
" Linking to vim highlight types
"
hi def link df_conditionals    Conditional
hi def link df_loops           Repeat
hi def link df_ctrl_flow       Special
hi def link df_boolean         Boolean
hi def link df_keyword         Keyword
hi def link df_directives      Macro
hi def link df_type            Type
hi def link df_complex_type    Structure
hi def link df_number          Number
hi def link df_operator        Operator
hi def link df_comment         Comment
hi def link df_proc            Function
hi def link df_string_literal  String
hi def link df_string_delim    String
hi def link df_char_literal    String
hi def link df_char_delim      String

let b:current_syntax = "dragonfly"

let &cpo = s:cpo_save
unlet s:cpo_save

