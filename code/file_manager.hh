#pragma once
#include <cstdint>

using FileID = int64_t;

struct FileLexInfo {
	FileID      file_id         = -1;
	char const* file_name       = nullptr;
	char const* raw_file_data   = nullptr;
	size_t      cursor_position = 0;
	size_t      line_position   = 1;
};

struct FileData {
	char const* name     = nullptr;
	char const* raw_data = nullptr;
	size_t      size     = 0;
};

void FileManager_Cleanup();

FileLexInfo FileManager_GetOrCreateFileInfo( char const* filepath );
FileData FileManager_GetFileData( FileID id );
