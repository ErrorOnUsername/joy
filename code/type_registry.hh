#pragma once

#include "ast.hh"


void TypeRegistry_Init();
void TypeRegistry_Shutdown();

void TypeRegistry_Register( Type* type );
TypeID TypeRegistry_GetID( Type* type );
