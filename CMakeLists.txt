cmake_minimum_required( VERSION 3.8 )
project( swarm CXX )

set( CMAKE_EXPORT_COMPILE_COMMANDS 1 )
set( CMAKE_CXX_STANDARD 20 )

set( SOURCES
	src/main.cc
	src/ast.cc
	src/compiler.cc
	src/job_system.cc
	src/lexer.cc
	src/main.cc
	src/parser.cc
	src/program.cc
	src/token.cc
	src/typechecker.cc
)

add_executable( ${CMAKE_PROJECT_NAME} ${SOURCES} )

add_custom_target( run
	COMMAND ./build/swarm
	VERBATIM
	WORKING_DIRECTORY ..
	DEPENDS swarm
)
