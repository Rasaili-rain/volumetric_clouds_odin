package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

SCREEN_WIDTH := 800
SCREEN_HEIGHT := 800

VERTEX_SHADER_PATH :: "vertexShader.glsl"
FRAGMENT_SHADER_PATH :: "fragmentShader.glsl"

Shader_State :: struct {
	shader:       rl.Shader,
	u_time:       i32,
	u_resolution: i32,
}

main :: proc() {
	context.logger = log.create_console_logger(
		opt = log.Options{.Level, .Terminal_Color, .Time, .Short_File_Path, .Line, .Procedure},
	)
	defer log.destroy_console_logger(context.logger)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(i32(SCREEN_WIDTH), i32(SCREEN_HEIGHT), "Raymarching")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	state, ok := load_shader_state()
	if !ok {
		log.error("Failed to load initial shader, exiting.")
		return
	}
	defer rl.UnloadShader(state.shader)

	for !rl.WindowShouldClose() {
		if rl.IsWindowResized() {
			SCREEN_WIDTH = int(rl.GetScreenWidth())
			SCREEN_HEIGHT = int(rl.GetScreenHeight())
		}

		if rl.IsKeyPressed(.F5) {
			reload_shader(&state)
		}

		time := f32(rl.GetTime())
		resolution := [2]f32{f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}

		rl.SetShaderValue(state.shader, state.u_time, &time, .FLOAT)
		rl.SetShaderValue(state.shader, state.u_resolution, &resolution, .VEC2)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		rl.BeginShaderMode(state.shader)
		rl.DrawRectangle(0, 0, i32(SCREEN_WIDTH), i32(SCREEN_HEIGHT), rl.WHITE)
		rl.EndShaderMode()

		rl.DrawText(fmt.ctprint("FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		rl.DrawText("F5: reload shader", 10, 35, 10, rl.WHITE)

		rl.EndDrawing()
	}
}

load_shader_state :: proc() -> (state: Shader_State, ok: bool) {
	vertex_source := load_shader_file(VERTEX_SHADER_PATH) or_return
	fragment_source := load_shader_file(FRAGMENT_SHADER_PATH) or_return
	defer delete(vertex_source)
	defer delete(fragment_source)

	vert_cstr := strings.clone_to_cstring(vertex_source)
	frag_cstr := strings.clone_to_cstring(fragment_source)
	defer delete(vert_cstr)
	defer delete(frag_cstr)

	shader := rl.LoadShaderFromMemory(vert_cstr, frag_cstr)
	if shader.id == 0 {
		log.error("Failed to load shader into GPU memory!")
		return {}, false
	}

	state = Shader_State {
		shader       = shader,
		u_time       = rl.GetShaderLocation(shader, "uTime"),
		u_resolution = rl.GetShaderLocation(shader, "uResolution"),
	}
	return state, true
}


reload_shader :: proc(state: ^Shader_State) {
	new_state, ok := load_shader_state()
	if !ok {
		log.warn("Reload failed, keeping previous shader.")
		return
	}

	rl.UnloadShader(state.shader)
	state^ = new_state
	log.info("Shader reloaded successfully.")
}

load_shader_file :: proc(filename: string) -> (source: string, ok: bool) {
	data, err := os.read_entire_file(filename, context.allocator)
	if err == nil {return string(data), true}
	log.errorf("Error loading shader file: %s (Error code: %v)", filename, err)
	return "", false
}
