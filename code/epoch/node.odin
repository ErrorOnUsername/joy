package epoch

import "core:mem"


AnyNode :: union
{
	^AddNode,
}

Node :: struct
{
	inputs: []^Node,
}

AddNode :: struct
{
	using node: Node,
}

