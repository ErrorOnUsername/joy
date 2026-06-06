package opto

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"


LinkSection :: struct {
	type: SectionType,
	data: []u8,
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

	init_code(ctx, &lc) or_return

	link_non_text(ctx, &lc) or_return

	link_internal_text(ctx, &lc) or_return

	create_and_write_object_file(ctx, &lc) or_return

	return true
}

init_code :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
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

	return true
}

link_non_text :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
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

	rodata.data = make([]u8, len(rodata_buf))
	copy(rodata.data, rodata_buf[:])

	data.data = make([]u8, len(data_buf))
	copy(data.data, data_buf[:])

	bss.data = make([]u8, len(bss_buf))
	copy(bss.data, bss_buf[:])

	return true
}

link_internal_text :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
	arch := arch_impl(.Amd64)
	mod_head := ctx.modules
	for mod_head != nil {
		mod := &mod_head.el
		for sym in mod.symbols {
			#partial switch s in sym.derived {
				case ^Function:
					for relo in s.output.relos {
						if relo.is_local do continue
						n := relo.n
						assert(n.kind == .Call)
						call_target := n.inputs[2]
						assert(call_target.kind == .Symbol)
						sym_ex := call_target.extra.derived.(^SymbolExtra)
						sym_name := sym_ex.sym.name
						assert(sym_name in lc.symbol_offsets)
						target_start := lc.symbol_offsets[sym_name].offset
						fn_start := lc.symbol_offsets[s.name].offset
						start := fn_start + relo.offset
						arch.patch_local_relo(s, n, start, target_start)
					}
			}
		}
		mod_head = mod_head.next
	}
	return true
}

create_and_write_object_file :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
	create_and_write_pe_object(ctx, lc) or_return
	return true
}

obj_write_bytes :: proc(out: ^[dynamic]u8, d: ^$T) {
	append(out, ..slice.bytes_from_ptr(d, size_of(T)))
}

create_and_write_pe_object :: proc(ctx: ^OptoContext, lc: ^LinkContext) -> bool {
	file_data: [dynamic]u8
	defer delete(file_data)

	pe_write_dos_stub(&file_data) or_return

	low_date_time := u32(0xFFFFFFFF & time.time_to_unix(time.now()))

	header := PEHeader {
		magic = 0x0000_4550, // literally "PE\0\0"
		machine = .Amd64,
		section_count = len(lc.sections),
		time_date_stamp = low_date_time,
		symbol_table_pointer = 0,
		symbol_count = 0,
		optional_header_size = size_of(PE64OptionalHeader),
		characteristics = { .ExecutableImage },
	}

	optional_header := PE64OptionalHeader {
		magic = PE_OPTIONAL_HEADER64_MAGIC,
		major_linker_version = 6,
		minor_linker_version = 7,
		size_of_code = 0,
		size_of_initialized_data = 0,
		size_of_uninitialized_data = 0,
		address_of_entry_point = 0,
		base_of_code = 0,
		image_base = PE_EXE_IMAGE_BASE, // Default for .EXEs
		section_alignment = 0,
		file_alignment = 0,
		major_operating_system_version = 10,
		minor_operating_system_version = 0,
		major_image_version = 1,
		minor_image_version = 0,
		major_subsystem_version = 6,
		minor_subsystem_version = 4,
		win32_version_value = 0,
		size_of_image = 0,
		size_of_headers = 0,
		checksum = 0,
		subsystem = .WindowsCUI,
		dll_characteristics = { },
		size_of_stack_reserve = 0,
		size_of_stack_commit = 0,
		size_of_heap_reserve = 0,
		size_of_heap_commit = 0,
		loader_flags_DEPRECATED = 0,
		number_of_rva_and_sizes = 16,
		data_directories = { },
	}

	obj_write_bytes(&file_data, &header)
	obj_write_bytes(&file_data, &optional_header)

	exe_write_err := os.write_entire_file("test.exe", file_data[:])
	if exe_write_err != nil {
		fmt.eprintln("Failed to write the executable file 'test.exe': {}", exe_write_err)
		return false
	}

	// Just PE shit from here on...

	PEMachine :: enum(u16) {
		Unknown = 0,
		Amd64 = 0x8664,
	}

	PECharacteristics :: enum(u16) {
		RelocsStripped,
		ExecutableImage,
		LineNumsStripped_Deprecated,
		LocalSymsStripped_Deprecated,
		AggressiveWSTrim_Deprecated,
		LargeAddressAware,
		Reserved0,
		BytesReversedLow_Deprecated,
		Machine32Bits,
		DebugStripped,
		Removable_RunFromSwap,
		Net_RunFromSwap,
		System,
		DLL,
		UniprocessorMachineOnly,
		BytesReversedHigh_Deprecated,

	}
	PECharacteristicFlags :: bit_set[PECharacteristics]

	PEHeader :: struct {
		magic: u32,
		machine: PEMachine,
		section_count: u16,
		time_date_stamp: u32,
		symbol_table_pointer: u32,
		symbol_count: u32,
		optional_header_size: u16,
		characteristics: PECharacteristicFlags,
	}

	PEDataDirectoryEntry :: enum {
		Export,
		Import,
		Resource,
		Exception,
		Security,
		BaserLoc,
		Debug,
		Architecture,
		GlobalPtr,
		TLS,
		LoadConfig,
		BoundImport,
		IAT,
		DelayImport,
		COMDescriptor,
		Reserved0,
	}

	PE_EXE_IMAGE_BASE :: 0x400000
	PE_OPTIONAL_HEADER32_MAGIC :: 0x10B
	PE_OPTIONAL_HEADER64_MAGIC :: 0x20B
	PE_OPTIONAL_ROM_HEADER_MAGIC :: 0x107

	PE64OptionalHeader :: struct {
		magic: u16,
		major_linker_version: u8,
		minor_linker_version: u8,
		size_of_code: u32,
		size_of_initialized_data: u32,
		size_of_uninitialized_data: u32,
		address_of_entry_point: u32,
		base_of_code: u32,
		image_base: u64,
		section_alignment: u32,
		file_alignment: u32,
		major_operating_system_version: u16,
		minor_operating_system_version: u16,
		major_image_version: u16,
		minor_image_version: u16,
		major_subsystem_version: u16,
		minor_subsystem_version: u16,
		win32_version_value: u32,
		size_of_image: u32,
		size_of_headers: u32,
		checksum: u32,
		subsystem: PESubsystem,
		dll_characteristics: PEDLLCharacteristicFlags,
		size_of_stack_reserve: u64,
		size_of_stack_commit: u64,
		size_of_heap_reserve: u64,
		size_of_heap_commit: u64,
		loader_flags_DEPRECATED: u32,
		number_of_rva_and_sizes: u32,
		data_directories: [PEDataDirectoryEntry]PEDataDirectory,
	}

	PESubsystem :: enum(u16) {
		Unknown,
		Native,
		WindowsGUI,
		WindowsCUI,
		Reserved0,
		OS2CUI,
		Reserved1,
		POSIXCUI,
		Reserved2,
		WindowsCEGUI,
		EFIApplication,
		EFIBootServiceDriver,
		EFIRuntimeDriver,
		EFIROM,
		XBox,
		Reserved3,
		WindowsBootApplication,
	}

	PEDLLCharacteristics :: enum(u16) {
		Reserved0,
		Reserved1,
		Reserved2,
		Reserved3,
		Reserved4,
		HighEntropyVA,
		DynamicBase,
		ForceIntegrity,
		NXCompat,
		NoIsolation,
		NoSEH,
		NoBind,
		AppContainer,
		WDMDriver,
		GuardCF,
		TerminalServerAware,
	}
	PEDLLCharacteristicFlags :: bit_set[PEDLLCharacteristics]

	PEDataDirectory :: struct {
		virtual_address: u32,
		size: u32,
	}

	PESectionHeader :: struct {
		name: u64,
		virtual_size: u32,
		virtual_addr: u32,
		size_of_raw_data: u32,
		pointer_to_raw_data: u32,
		pointer_to_relocations: u32,
		pointer_to_linenumbers: u32,
		number_of_relocations: u16,
		number_of_linenumbers: u16,
		characteristics: u32,
	}

	PESectionCharacteristics :: enum(u32) {
		Reserved0                 = 0x00000000,
		Reserved1                 = 0x00000001,
		Reserved2                 = 0x00000002,
		Reserved3                 = 0x00000004,
		NoPad                     = 0x00000008,
		Reserved4                 = 0x00000010,
		ContainsCode              = 0x00000020,
		ContainsInitializedData   = 0x00000040,
		ContainsUninitializedData = 0x00000080,
		Linker_Other_Reserved5    = 0x00000100,
		Linker_Info               = 0x00000200,
		Reserved6                 = 0x00000400,
		Linker_Remove             = 0x00000800,
		Linker_COMDAT             = 0x00001000,
		GPRelative                = 0x00008000,
		Mem_Purgeable_Reserved7   = 0x00020000,
		Mem_16Bit_Reserved8       = 0x00020000,
		Mem_Locked_Reserved9      = 0x00040000,
		Mem_Preload_Reserved10    = 0x00080000,
		Align1Bytes               = 0x00100000,
		Align2Bytes               = 0x00200000,
		Align4Bytes               = 0x00300000,
		Align8Bytes               = 0x00400000,
		Align16Bytes              = 0x00500000,
		Align32Bytes              = 0x00600000,
		Align64Bytes              = 0x00700000,
		Align128Bytes             = 0x00800000,
		Align256Bytes             = 0x00900000,
		Align512Bytes             = 0x00A00000,
		Align1024Bytes            = 0x00B00000,
		Align2048Bytes            = 0x00C00000,
		Align4096Bytes            = 0x00D00000,
		Align8192Bytes            = 0x00E00000,
		Linker_ReloOverflow       = 0x01000000,
		Mem_Discardable           = 0x02000000,
		Mem_NotCached             = 0x04000000,
		Mem_NotPaged              = 0x08000000,
		Mem_Shared                = 0x10000000,
		Mem_Execute               = 0x20000000,
		Mem_Read                  = 0x40000000,
		Mem_Write                 = 0x80000000,
	}

	return true
}

pe_write_dos_stub :: proc(out: ^[dynamic]u8) -> bool {
	dos_header := DOSHeader {
		magic = 0x5A4D, // "MZ"
		bytes_in_last_page = 90,
		page_count = 3,
		relo_count = 0,
		header_size_in_paragraphs = 4,
		min_extra_paragraphs = 0,
		max_extra_paragraphs = 0xFFFF,
		initial_rel_ss_val = 0,
		initial_sp_val = 0xB8,
		checksum = 0,
		initial_ip_value = 0,
		initial_rel_cs_value = 0,
		relo_table_file_addr = 0x40, // Directly after this header (but its empty so there aint shit there)
		overlay_number = 0,
		reserved_0 = {},
		oem_id = 0,
		oem_info = 0,
		reserved_1 = {},
		file_addr_of_pe_header = 0x100, // header + code + rich header
	}

	stub_code := [64]u8 {
		0x0E,             // push %cs
		0x1F,             // pop %ds
		0xBA, 0x0E, 0x00, // mov $0x0E, %dx
		0xB4, 0x09,       // mov $9, %ah
		0xCD, 0x21,       // int $0x21 ; DOS Serivce 9 (Display String)
		0xB8, 0x01, 0x4C, // mov $0x4C01, %ax
		0xCD, 0x21,       // int $0x21 ; DOS 2.0+ Serivce 4C (Terminate with Return Code 1)
		// "This program cannot be run in DOS mode.\r\r\n$"
		0x54, 0x68, 0x69, 0x73, 0x20, 0x70, 0x72, 0x6F, 0x67, 0x72, 0x61, 0x6D, 0x20, 0x63, 0x61, 0x6E, 0x6E,
		0x6F, 0x74, 0x20, 0x62, 0x65, 0x20, 0x72, 0x75, 0x6E, 0x20, 0x69, 0x6E, 0x20, 0x44, 0x4F, 0x53, 0x20,
		0x6D, 0x6F, 0x64, 0x65, 0x2E, 0x0D, 0x0D, 0x0A, 0x24,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 // padding
	}

	// This is useless for us so its just zeros, but normally it would have tool metadata (versions and such) for the official MSFT toochain
	rich_header: [128]u8

	obj_write_bytes(out, &dos_header)
	append(out, ..stub_code[:])
	append(out, ..rich_header[:])

	DOSHeader :: struct {
		magic:                     u16,
		bytes_in_last_page:        u16,
		page_count:                u16, // page = 512 bytes
		relo_count:                u16,
		header_size_in_paragraphs: u16, // "paragraphs"... gotta love DOS :D (it's just the term for a 16 bytes)
		min_extra_paragraphs:      u16,
		max_extra_paragraphs:      u16,
		initial_rel_ss_val:        u16,
		initial_sp_val:            u16,
		checksum:                  u16,
		initial_ip_value:          u16,
		initial_rel_cs_value:      u16,
		relo_table_file_addr:      u16,
		overlay_number:            u16,
		reserved_0:                [4]u16,
		oem_id:                    u16,
		oem_info:                  u16,
		reserved_1:                [10]u16,
		file_addr_of_pe_header:    u32,
	}
	return true
}

