package main

import "core:fmt"
import "core:os"


main :: proc()
{
	if !parse_args() || g_cl_state.mode == .Help {
		return
	}

	assert( g_cl_state.mode == .Build || g_cl_state.mode == .BuildAndRun )

	compiler_init()
	defer compiler_deinit()

	init_default_types()

	id, ok := fm_open( "test/basic" )
	if !ok {
		fmt.eprintln( "Could not load file" )
		return
	}

	compiler_enqueue_work( .ParsePackage, id )

	tasks_failed := compiler_finish_work()
	if tasks_failed != 0 {
		fmt.printf( "Parsing phase failed! ({} task(s) reported errors)\n", tasks_failed )
		fmt.println( "Compilation failed" )
		return
	}

	root_package_data := fm_get_data( id )
	pkg := root_package_data.pkg

	packages_to_check, pkgs_ok := tc_build_package_list( pkg )
	if !pkgs_ok {
		return
	}

	c: Checker

	tasks_failed = tc_initialize( &c, packages_to_check )
	if tasks_failed != 0 {
		fmt.printf( "Typechecking phase failed! ({} task(s) reported errors)\n", tasks_failed )
		fmt.println( "Compilation failed" )
		return
	}

	tasks_failed = compiler_check_all( &c )
	if tasks_failed != 0 {
		fmt.printf( "Typechecking phase failed! ({} task(s) reported errors)\n", tasks_failed )
		fmt.println( "Compilation failed" )
		return
	}

	fmt.println( pkg )

	fmt.println( "Compilation successful" )
}
