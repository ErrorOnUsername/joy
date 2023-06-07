#include "file_manager.hh"
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "assert.hh"
#include "profiling.hh"

static constexpr size_t MAX_MODULE_COUNT = 256;

static std::mutex s_file_manager_mutex;

static std::vector<FileData>                   s_file_data_table;
static std::unordered_map<std::string, FileID> s_file_id_map;


void FileManager_Cleanup()
{
	for ( FileData file_data : s_file_data_table )
	{
		free( (void*)file_data.name );
		free( (void*)file_data.raw_data );
	}

	s_file_data_table.clear();
	s_file_id_map.clear();
}


FileLexInfo FileManager_GetOrCreateFileInfo( char const* filepath )
{
	TIME_PROC();

	std::scoped_lock<std::mutex> lock( s_file_manager_mutex );

	auto find_iter = s_file_id_map.find( filepath );
	if ( find_iter != s_file_id_map.cend() )
	{
		return FileLexInfo {
			.file_id         = find_iter->second,
			.file_name       = s_file_data_table[find_iter->second].name,
			.raw_file_data   = s_file_data_table[find_iter->second].raw_data,
			.cursor_position = 0,
		};
	}

	FILE* file = fopen( filepath, "rb" );
	DF_ASSERT( file, "Could not open file '%s'\n", filepath );

	fseek( file, 0, SEEK_END );
	size_t file_size = ftell( file );
	fseek( file, 0, SEEK_SET );

	char* data = (char*)malloc( file_size + 1 );
	data[file_size] = 0;

	fread( data, 1, file_size, file );

	fclose( file );

	FileID id = s_file_data_table.size();
	s_file_id_map[filepath] = id;

	size_t path_size = strlen( filepath );

	char* name = (char*)malloc( path_size + 1 );
	memcpy( name, filepath, path_size );

	name[path_size] = 0;

	FileData file_data = {
		.name     = (const char*)name,
		.raw_data = (const char*)data,
		.size     = file_size,
	};

	s_file_data_table.push_back( file_data );

	return FileLexInfo {
		.file_id         = id,
		.file_name       = file_data.name,
		.raw_file_data   = file_data.raw_data,
		.cursor_position = 0,
	};
}


FileData FileManager_GetFileData( FileID id )
{
	std::scoped_lock<std::mutex> lock( s_file_manager_mutex );

	DF_ASSERT( (size_t)id < s_file_data_table.size(), "Invalid file id: %d", id );
	return s_file_data_table[id];
}
