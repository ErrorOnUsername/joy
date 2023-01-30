#pragma once
#include <cassert>
#include <cstdint>
#include <cstdlib>

struct Arena {
	uint8_t* data;
	size_t next_alloc_offset;
	size_t size;

	Arena(size_t capacity)
		: data(nullptr)
		, next_alloc_offset(0)
		, size(capacity)
	{
		data = (uint8_t*)malloc(size);
		memset(data, 0, size);
	}

	void* alloc_bytes(size_t bytes)
	{
		assert(next_alloc_offset + bytes <= size);
		void* ptr = data + next_alloc_offset;
		next_alloc_offset += bytes;
		return ptr;
	}

	void clear()
	{
		next_alloc_offset = 0;
	}
};
