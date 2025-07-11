package main

import "base:intrinsics"
import "core:mem"
import "core:os"
import "core:thread"


PumpAction :: enum {
	ParsePackage,
	ParseFile,
	InitializeScopes,
	CheckPackage,
	CheckProcBody,
}

PumpResult :: enum {
	Continue,
	Error,
}

WorkerData :: struct {
	action:     PumpAction,
	file_id:    FileID,
	result:     PumpResult,
	pkg:        ^Package,
	checker:    ^Checker,
	module:     ^Module,
	proc_proto: ^ProcProto,
}

PriorityItem :: struct (T: typeid) {
	priority: int,
	item: T,
}


failed_task_count := 0
job_data_raw_pool := [32768]byte { }
job_data_arena: mem.Arena
job_data_allocator: mem.Allocator
job_pool: thread.Pool


@(thread_local)
@(private="file")
tl_ast_pool: mem.Dynamic_Pool

@(thread_local)
tl_ast_allocator: mem.Allocator

@(thread_local)
@(private="file")
thread_data_initialized: bool


compiler_init :: proc() {
	thread.pool_init(&job_pool, context.allocator, os.processor_core_count())
	thread.pool_start(&job_pool)

	mem.arena_init(&job_data_arena, job_data_raw_pool[:])
	job_data_allocator = mem.arena_allocator(&job_data_arena)
}

compiler_deinit :: proc() {
	thread.pool_join(&job_pool)
	thread.pool_destroy(&job_pool)
}

compiler_finish_work :: proc() -> int {
	// We just finish up all the work, all the while poping out work to help it along
	for task in thread.pool_pop_waiting(&job_pool) {
		thread.pool_do_work(&job_pool, task)
	}

	// Make sure everything is done
	for thread.pool_num_outstanding(&job_pool) != 0 { }
	return failed_task_count
}

compiler_enqueue_work :: proc(
	action: PumpAction,
	file_id: FileID = 0,
	pkg: ^Package = nil,
	checker: ^Checker = nil,
	proc_proto: ^ProcProto = nil,
	module: ^Module = nil
) {
	data_ptr := new(WorkerData, job_data_allocator)
	data_ptr.action     = action
	data_ptr.file_id    = file_id
	data_ptr.pkg        = pkg
	data_ptr.checker    = checker
	data_ptr.module     = module
	data_ptr.proc_proto = proc_proto

	thread.pool_add_task(&job_pool, context.allocator, threading_proc, data_ptr)
}


threading_proc :: proc(task: thread.Task) {
	if !thread_data_initialized {
		mem.dynamic_pool_init(&tl_ast_pool)
		tl_ast_allocator = mem.dynamic_pool_allocator(&tl_ast_pool)

		thread_data_initialized = true
	}

	task_data := cast(^WorkerData)task.data
	task_data.result = compiler_pump(task_data)

	if task_data.result == .Error {
		intrinsics.atomic_add(&failed_task_count, 1)
	}
}

compiler_pump :: proc(wd: ^WorkerData) -> PumpResult {
	switch wd.action {
		case .ParsePackage:
			return pump_parse_package(wd.file_id)
		case .ParseFile:
			return pump_parse_file(wd.file_id)
		case .InitializeScopes:
			return pump_tc_init_scopes(wd.file_id, wd.checker)
		case .CheckPackage:
			return pump_tc_check_pkg(wd.checker, wd.pkg)
		case .CheckProcBody:
			return pump_tc_check_proc_body(wd.checker, wd.proc_proto, wd.module)
	}

	return .Continue
}
