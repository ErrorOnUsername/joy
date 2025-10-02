package viz

import "core:fmt"
import "core:os"

import "vendor:glfw"
import gl "vendor:OpenGL"


app: AppContext
AppContext :: struct {
	running: bool,
}


GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 1

main :: proc() {
	if !glfw.Init() {
		fmt.println("Failed to initialize GLFW")
		return
	}
	defer glfw.Terminate()

	when os.OS == .Darwin {
		glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
		glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
		glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, 1)
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	}

	wnd := glfw.CreateWindow(1280, 720, "Epoch Visualizer", nil, nil)
	defer glfw.DestroyWindow(wnd)

	glfw.MakeContextCurrent(wnd)
	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	fmt.println("OpenGL Info:")
	fmt.println("  Vendor:", gl.GetString(gl.VENDOR))
	fmt.println("  Renderer:", gl.GetString(gl.RENDERER))
	fmt.println("  Version:", gl.GetString(gl.VERSION))

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	glfw.SwapInterval(1)

	window_key_callback :: proc "c" (wnd: glfw.WindowHandle, key, scancode, action, mods: i32) {
		if action == glfw.PRESS || action == glfw.REPEAT {
			pump_event(.Key, int(key), int(action == glfw.REPEAT))
		}
	}

	window_mouse_pos_callback :: proc "c" (wnd: glfw.WindowHandle, x, y: f64) {
		pump_event(.MouseMove, int(transmute(i32)f32(x)), int(transmute(i32)f32(y)))
	}

	window_scroll_callback :: proc "c" (wnd: glfw.WindowHandle, xoff, yoff: f64) {
		pump_event(.MouseScroll, int(transmute(i32)f32(xoff)), int(transmute(i32)f32(yoff)))
	}

	window_mouse_button_callback :: proc "c" (wnd: glfw.WindowHandle, button, action, mods: i32) {
		mbutton: MouseButton
		switch button {
			case glfw.MOUSE_BUTTON_1:
				mbutton = .Button1
			case glfw.MOUSE_BUTTON_2:
				mbutton = .Button2
		}

		ev: EventType
		switch action {
			case glfw.PRESS:
				ev = .MouseButtonPressed
			case glfw.RELEASE:
				ev = .MouseButtonReleased
		}

		pump_event(ev, int(mbutton), 0)
	}

	window_close_callback :: proc "c" (wnd: glfw.WindowHandle) {
		pump_event(.Quit, 0, 0)
	}

	glfw.SetKeyCallback(wnd, window_key_callback)
	glfw.SetCursorPosCallback(wnd, window_mouse_pos_callback)
	glfw.SetScrollCallback(wnd, window_scroll_callback)
	glfw.SetMouseButtonCallback(wnd, window_mouse_button_callback)
	glfw.SetWindowCloseCallback(wnd, window_close_callback)

	gl.ClearColor(0.8, 0.18, 0.8, 1.0)

	app.running = true
	for app.running {
		glfw.PollEvents()

		gl.Clear(gl.COLOR_BUFFER_BIT)

		glfw.SwapBuffers(wnd)
	}
}


MouseButton :: enum {
	Button1,
	Button2
}
EventType :: enum {
	Quit,
	Key,
	MouseButtonPressed,
	MouseButtonReleased,
	MouseMove,
	MouseScroll,
}

pump_event :: proc "contextless" (ev: EventType, data0: int, data1: int) {
	switch ev {
		case .Quit:
			app.running = false
		case .Key:
		case .MouseButtonPressed:
		case .MouseButtonReleased:
		case .MouseMove:
		case .MouseScroll:
	}
}

