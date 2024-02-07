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

	id, ok := fm_open( "test/basic" )
	if !ok {
		fmt.eprintln( "Could not load file" )
		return
	}

	tasks_failed := exec_phases( id )

	if tasks_failed != 0 {
		fmt.printf( "Compilation Failed! ({} tasks reported errors)\n", tasks_failed )
		os.exit( 1 )
	}

	fmt.println( "Compilation Successful" ) }


exec_phases :: proc( root_id: FileID ) -> int
{
	compiler_enqueue_work( .ParsePackage, root_id )

	tasks_failed := compiler_finish_work()
	if tasks_failed != 0 do return tasks_failed

	root_package_data := fm_get_data( root_id )
	pkg := root_package_data.pkg

	/*
	init_default_types()

	packages_to_check, pkgs_ok := tc_build_package_list( pkg )
	if !pkgs_ok {
		return 1
	}

	c: Checker

	tasks_failed = tc_initialize_scopes( &c, packages_to_check )
	if tasks_failed != 0 do return tasks_failed

	tasks_failed = tc_check_package_dag( &c, packages_to_check )
	if tasks_failed != 0 do return tasks_failed

	tasks_failed = tc_check_proc_bodies( &c )
	if tasks_failed != 0 do return tasks_failed
	*/

	return 0
}

