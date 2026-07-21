package main

import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

main :: proc() {
	screen_width := 800
	screen_height := 800

	rl.InitWindow(i32(screen_width), i32(screen_height), "FPS")
	// rl.SetTargetFPS(60)

	// Load shaders from files
	vertex_shader := load_shader_file("vertex.glsl")
	fragment_shader := load_shader_file("fragment.glsl")
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
		fmt.println("Failed to load shader!")
		return
	}

	u_resolution := rl.GetShaderLocation(shader, "uResolution")

	for !rl.WindowShouldClose() {
		resolution := [2]f32{f32(screen_width), f32(screen_height)}
		rl.SetShaderValue(shader, u_resolution, &resolution, .VEC2)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		// Draw a rectangle with the shader
		rl.BeginShaderMode(shader)
		rl.DrawRectangle(0, 0, i32(screen_width), i32(screen_height), rl.WHITE)
		rl.EndShaderMode()

		// Draw UV info text
		rl.DrawText(fmt.ctprint("UV Mango - FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)

		rl.EndDrawing()
	}

	rl.CloseWindow()
}

load_shader_file :: proc(filename: string) -> string {
	data, err := os.read_entire_file(filename, context.allocator)
	if err != nil {
		fmt.eprintln("Error loading shader file:", filename)
		assert(false)
	}
	return string(data)
}
