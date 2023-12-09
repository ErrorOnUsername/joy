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

	compiler_enqueue_work( .ParsePackage, id )

	tasks_failed := compiler_finish_work()
	if tasks_failed != 0 {
		fmt.printf( "Parsing phase failed! ({} task(s) reported errors)\n", tasks_failed )
		fmt.println( "Compilation failed" )
		return
	}

	root_package_data := fm_get_data( id )
	pkg := root_package_data.pkg

	packages_to_check, pkgs_ok := checker_build_package_list( pkg )
	if !pkgs_ok {
		return
	}

	checker_initialize_symbol_tables( packages_to_check )
	checker_collect_proc_signatures( packages_to_check )

	working_prio := 0
	for prio_pkg in &packages_to_check {
		if prio_pkg.priority != working_prio {
			tasks_failed = compiler_finish_work()
			if tasks_failed > 0 do break
		}

		for mod in prio_pkg.item.modules {
			compiler_enqueue_work( .CheckModule, mod.file_id )
		}
	}

	tasks_failed = compiler_finish_work()
	if tasks_failed != 0 {
		fmt.printf( "Typechecking phase failed! ({} tasks reported errors)\n", tasks_failed )
		return
	}


	fmt.println( pkg )

	fmt.println( "Compilation successful" )
}
