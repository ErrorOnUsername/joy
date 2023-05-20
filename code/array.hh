#pragma once
#include <cassert>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <type_traits>


template<typename ElemType>
struct Array {
	ElemType* data;
	size_t    capacity;
	size_t    count;


	Array( size_t initial_capacity = 0 )
		: data( nullptr )
		, capacity( initial_capacity )
		, count( 0 )
	{
		if ( initial_capacity == 0 ) return;

		data = (ElemType*)malloc( initial_capacity * sizeof( ElemType ) );
		memset( data, 0, initial_capacity * sizeof( ElemType ) );
	}


	void resize( size_t new_capacity )
	{
		if ( new_capacity == capacity ) return;

		if ( new_capacity < count )
		{
			for ( size_t i = new_capacity; i < count; i++ )
			{
				if constexpr ( std::is_destructible<ElemType>::value )
				{
					( &data[i] )->~ElemType();
				}
			}
		}

		void* new_data = malloc( new_capacity * sizeof( ElemType ) );

		if ( data )
		{
			memcpy( new_data, (void*)data, new_capacity * sizeof( ElemType ) );
			free( data );
		}

		data     = (ElemType*)new_data;
		capacity = new_capacity;
		count    = ( new_capacity < count ) ? new_capacity : count;
	}


	void append( ElemType& item )
	{
		if ( count == capacity )
		{
			resize( capacity == 0 ? 1 : capacity * 2 );
		}

		new ( data + count ) ElemType( item );

		count++;
	}


	void clear()
	{
		free( (void*)data );

		data     = nullptr;
		capacity = 0;
		count    = 0;
	}


	void swap( Array<ElemType> other )
	{
		if ( data )
		{
			free( data );
		}

		data     = other.data;
		capacity = other.capacity;
		count    = other.count;

		other.data     = nullptr;
		other.capacity = 0;
		other.count    = 0;
	}


	ElemType& operator[] ( size_t index )
	{
		assert( index < capacity );
		return data[index];
	}
};
