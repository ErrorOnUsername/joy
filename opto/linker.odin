package opto

import "core:fmt"


LinkSection :: struct {
	type: SectionType,
	data: []u8,

	start_file: int,
	end_file: int,
}

SectionType :: enum {
	Code,
	BSS,
	Data,
	ROData,
}

LinkSymbolOffset :: struct {
	section_type: SectionType,
	offset: int,
}

LinkContext :: struct {
	symbol_offsets: map[string]LinkSymbolOffset,
	sections: [SectionType]LinkSection,
}

link_program :: proc(ctx: ^OptoContext) -> bool {
	lc: LinkContext

	text_size := init_code(ctx, &lc) or_return

	link_non_text(ctx, &lc, text_size) or_return

	link_text(ctx, &lc) or_return

	return true
}

init_code :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> (int, bool) {
	code_size := 0

	// sizing shit up
	mod_head := ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Function:
					fmt.assertf(!(s.name in lc.symbol_offsets), "duplicated symbol '{}'", s.name)
					so: LinkSymbolOffset
					so.section_type = .Code
					so.offset = code_size
					lc.symbol_offsets[s.name] = so

					code_size += len(s.output.data)
			}
		}
		mod_head = mod_head.next
	}

	lc.sections[.Code].data = make([]u8, code_size)

	// actually do the copy
	copy_pos := 0
	mod_head = ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Function:
					fn_size := len(s.output.data)
					copy_end := copy_pos + fn_size
					set_slice := lc.sections[.Code].data[copy_pos:copy_end]
					assert(len(set_slice) == fn_size)
					copy(set_slice, s.output.data[:])
					copy_pos += fn_size
			}
		}
		mod_head = mod_head.next
	}

	assert(code_size == copy_pos)

	lc.sections[.Code].start_file = 0 // FIXME: file header
	lc.sections[.Code].end_file = code_size

	return code_size, true
}

link_non_text :: proc(ctx: ^OptoContext, lc: ^LinkContext, text_end: int) -> bool {
	bss := &lc.sections[.BSS]
	bss.type = .BSS
	data := &lc.sections[.Data]
	data.type = .Data
	rodata := &lc.sections[.ROData]
	rodata.type = .ROData

	bss_buf: [dynamic]u8
	defer delete(bss_buf)
	data_buf: [dynamic]u8
	defer delete(data_buf)
	rodata_buf: [dynamic]u8
	defer delete(rodata_buf)

	mod_head := ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Global:
					fmt.assertf(!(s.name in lc.symbol_offsets), "duplicated symbol '{}'", s.name)

					so: LinkSymbolOffset

					is_const := false // FIXME: hook into types and shit
					if len(s.data) > 0 && is_const {
						so.offset = len(rodata_buf)
						so.section_type = .ROData
						append(&rodata_buf, ..s.data)
					} else if len(s.data) > 0 && !is_const {
						so.offset = len(data_buf)
						so.section_type = .Data
						append(&data_buf, ..s.data)
					} else {
						panic("add types to bss'd globals")
					}

					lc.symbol_offsets[s.name] = so
			}
		}
		mod_head = mod_head.next
	}

	data_size := text_end
	rodata.data = make([]u8, len(rodata_buf))
	copy(rodata.data, rodata_buf[:])
	set_link_section_file_pos(rodata, data_size)
	data_size += len(rodata_buf)

	data.data = make([]u8, len(data_buf))
	copy(data.data, data_buf[:])
	set_link_section_file_pos(data, data_size)
	data_size += len(data_buf)

	bss.data = make([]u8, len(bss_buf))
	copy(bss.data, bss_buf[:])
	set_link_section_file_pos(bss, data_size)
	data_size += len(bss_buf)

	return true
}

set_link_section_file_pos :: proc(section: ^LinkSection, curr_pos: int) {
	section.start_file = curr_pos
	section.end_file = curr_pos + len(section.data)
}

link_text :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
	mod_head := ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Function:
			}
		}
		mod_head = mod_head.next
	}
	return true
}

