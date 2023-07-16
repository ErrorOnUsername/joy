cmake_minimum_required( VERSION 3.8 )
project( swarm CXX )

set( CMAKE_EXPORT_COMPILE_COMMANDS 1 )
set( CMAKE_CXX_STANDARD 20 )

set( CMAKE_BUILD_TYPE Debug )

set( OPTICK_INSTALL_TARGETS OFF CACHE BOOL "Disable installing since we're building directly from source" )
add_subdirectory( third_party/optick )

set( OPTICK_DLL_OUTPUT ${CMAKE_BINARY_DIR}/third_party/optick/OptickCored.dll )

include_directories( third_party/optick/src )

set( SOURCES
	code/compiler.cc
	code/main.cc
	code/file_manager.cc
	code/lexer.cc
	code/log.cc
	code/parser.cc
	code/token.cc
	code/typechecker.cc
	code/type_registry.cc
)

add_executable( ${CMAKE_PROJECT_NAME} ${SOURCES} )
target_link_libraries( ${CMAKE_PROJECT_NAME} OptickCore )

if( EXISTS ${OPTICK_DLL_OUTPUT} )
	file( COPY ${OPTICK_DLL_OUTPUT} DESTINATION ${CMAKE_BINARY_DIR} )
endif()

add_custom_target( run
	COMMAND ./build/swarm
	VERBATIM
	WORKING_DIRECTORY ..
	DEPENDS swarm
)
