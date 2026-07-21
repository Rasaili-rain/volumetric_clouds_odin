package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import rl "vendor:raylib"


SCREEN_WIDTH := 800
SCREEN_HEIGHT := 800

main :: proc() {
	context.logger = log.create_console_logger(
		opt = log.Options{.Level, .Terminal_Color, .Time, .Short_File_Path, .Line, .Procedure},
	)
	defer log.destroy_console_logger(context.logger)


	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(i32(SCREEN_WIDTH), i32(SCREEN_HEIGHT), "Raymarching")
	defer rl.CloseWindow()


	// Load shaders from files
	vertex_shader := load_shader_file("vertexShader.glsl")
	fragment_shader := load_shader_file("fragmentShader.glsl")
	defer delete(vertex_shader)
	defer delete(fragment_shader)

	vert_cstr := strings.clone_to_cstring(vertex_shader)
	frag_cstr := strings.clone_to_cstring(fragment_shader)
	defer delete(vert_cstr)
	defer delete(frag_cstr)

	shader := rl.LoadShaderFromMemory(vert_cstr, frag_cstr)
	defer rl.UnloadShader(shader)

	// Check if shader loaded successfully
	if shader.id == 0 {
		log.error("Failed to load shader into GPU memory!")
		return
	}

	u_time := rl.GetShaderLocation(shader, "uTime")
	u_resolution := rl.GetShaderLocation(shader, "uResolution")

	for !rl.WindowShouldClose() {
		if rl.IsWindowResized() {
			SCREEN_WIDTH = int(rl.GetScreenWidth())
			SCREEN_HEIGHT = int(rl.GetScreenHeight())
		}

		time := f32(rl.GetTime())
		resolution := [2]f32{f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)}

		rl.SetShaderValue(shader, u_time, &time, .FLOAT)
		rl.SetShaderValue(shader, u_resolution, &resolution, .VEC2)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		rl.BeginShaderMode(shader)
		rl.DrawRectangle(0, 0, i32(SCREEN_WIDTH), i32(SCREEN_HEIGHT), rl.WHITE)
		rl.EndShaderMode()

		rl.DrawText(fmt.ctprint("FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)

		rl.EndDrawing()
	}

}

load_shader_file :: proc(filename: string) -> string {
	data, err := os.read_entire_file(filename, context.allocator)
	if err == nil {return string(data)}
	log.errorf("Error loading shader file: %s (Error code: %v)", filename, err)
	panic("Shader file loading failed")
}
