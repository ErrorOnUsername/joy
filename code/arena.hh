#pragma once
#include <cassert>
#include <cstdint>
#include <cstdlib>


struct Arena {
	size_t   capacity;
	uint8_t* data;
	uint8_t* write_head;

	Arena( size_t initial_capacity )
		: capacity( initial_capacity )
		, data( nullptr )
		, write_head( nullptr )
	{
		data       = (uint8_t*)malloc( initial_capacity );
		write_head = data;
	}

	template<typename T>
	T* alloc()
	{
		assert( write_head < ( data + capacity ) );

		T* new_alloc = (T*)write_head;
		write_head += sizeof( T );

		return new_alloc;
	}

	size_t bytes_allocated()
	{
		return write_head - data;
	};
};
