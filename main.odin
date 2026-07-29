package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

SCREEN_WIDTH := 800
SCREEN_HEIGHT := 800

RENDER_SCALE :: 0.5 // render the raymarch shader at half resolution

VERTEX_SHADER_PATH :: "vertexShader.glsl"
FRAGMENT_SHADER_PATH :: "fragmentShader.glsl"
UPSCALE_SHADER_PATH :: "bicubicUpscale.glsl"

LOC_U_TIME :: 0
LOC_U_RESOLUTION :: 1
LOC_U_NOISE_TEX :: 2
LOC_U_BLUE_NOISE_TEX :: 3
LOC_U_FRAME :: 4

UP_LOC_U_TEXTURE :: 0
UP_LOC_U_TEXEL_SIZE :: 1
UP_LOC_U_FULL_SIZE :: 2

NOISE_TEXTURE_PATH :: "noise.png"
BLUE_NOISE_TEXTURE_PATH :: "blueNoise.png"

Shader_State :: struct {
	shader:             rl.Shader,
	noise_tex:          rl.Texture2D,
	noise_tex_loc:      i32,
	blue_noise_tex:     rl.Texture2D,
	blue_noise_tex_loc: i32,
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
	defer rl.UnloadTexture(state.noise_tex)
	defer rl.UnloadTexture(state.blue_noise_tex)

	upscale_shader := rl.LoadShader(nil, UPSCALE_SHADER_PATH)
	defer rl.UnloadShader(upscale_shader)

	render_w := i32(f32(SCREEN_WIDTH) * RENDER_SCALE)
	render_h := i32(f32(SCREEN_HEIGHT) * RENDER_SCALE)
	target := rl.LoadRenderTexture(render_w, render_h)
	defer rl.UnloadRenderTexture(target)

	frame_count: i32 = 0

	for !rl.WindowShouldClose() {
		if rl.IsWindowResized() {
			SCREEN_WIDTH = int(rl.GetScreenWidth())
			SCREEN_HEIGHT = int(rl.GetScreenHeight())
			rl.UnloadRenderTexture(target)
			render_w = i32(f32(SCREEN_WIDTH) * RENDER_SCALE)
			render_h = i32(f32(SCREEN_HEIGHT) * RENDER_SCALE)
			target = rl.LoadRenderTexture(render_w, render_h)
		}
		if rl.IsKeyPressed(.F5) {
			reload_shader(&state)
		}

		time := f32(rl.GetTime())
		resolution := [2]f32{f32(render_w), f32(render_h)}
		rl.SetShaderValue(state.shader, LOC_U_TIME, &time, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_RESOLUTION, &resolution, .VEC2)
		rl.SetShaderValue(state.shader, LOC_U_FRAME, &frame_count, .INT)

		// Pass 1: render raymarch shader into the low-res target
		rl.BeginTextureMode(target)
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(state.shader)
		rl.SetShaderValueTexture(state.shader, state.noise_tex_loc, state.noise_tex)
		rl.SetShaderValueTexture(state.shader, state.blue_noise_tex_loc, state.blue_noise_tex)
		rl.DrawRectangle(0, 0, render_w, render_h, rl.WHITE)
		rl.EndShaderMode()
		rl.EndTextureMode()

		// Pass 2: bicubic-upscale the low-res target to the screen
		texel_size := [2]f32{1.0 / f32(render_w), 1.0 / f32(render_h)}
		full_size := [2]f32{f32(render_w), f32(render_h)}
		rl.SetShaderValue(upscale_shader, UP_LOC_U_TEXEL_SIZE, &texel_size, .VEC2)
		rl.SetShaderValue(upscale_shader, UP_LOC_U_FULL_SIZE, &full_size, .VEC2)

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(upscale_shader)
		rl.SetShaderValueTexture(upscale_shader, UP_LOC_U_TEXTURE, target.texture)
		rl.DrawTexturePro(
			target.texture,
			rl.Rectangle{0, 0, f32(render_w), f32(render_h)},
			rl.Rectangle{0, 0, f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)},
			rl.Vector2{0, 0},
			0,
			rl.WHITE,
		)
		rl.EndShaderMode()

		rl.DrawText(fmt.ctprint("FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		rl.DrawText("F5: reload shader", 10, 35, 10, rl.WHITE)
		rl.EndDrawing()

		frame_count += 1
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

	noise_tex := rl.LoadTexture(NOISE_TEXTURE_PATH)
	if noise_tex.id == 0 {
		log.error("Failed to load noise texture!")
		rl.UnloadShader(shader)
		return {}, false
	}
	rl.SetTextureWrap(noise_tex, .REPEAT)
	rl.SetTextureFilter(noise_tex, .BILINEAR)

	blue_noise_tex := rl.LoadTexture(BLUE_NOISE_TEXTURE_PATH)
	if blue_noise_tex.id == 0 {
		log.error("Failed to load blue noise texture!")
		rl.UnloadShader(shader)
		rl.UnloadTexture(noise_tex)
		return {}, false
	}
	rl.SetTextureWrap(blue_noise_tex, .REPEAT)
	rl.SetTextureFilter(blue_noise_tex, .POINT)

	state = Shader_State {
		shader             = shader,
		noise_tex          = noise_tex,
		noise_tex_loc      = rl.GetShaderLocation(shader, "uNoiseTex"),
		blue_noise_tex     = blue_noise_tex,
		blue_noise_tex_loc = rl.GetShaderLocation(shader, "uBlueNoiseTex"),
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
	rl.UnloadTexture(state.noise_tex)
	rl.UnloadTexture(state.blue_noise_tex)
	state^ = new_state
	log.info("Shader reloaded successfully.")
}

load_shader_file :: proc(filename: string) -> (source: string, ok: bool) {
	data, err := os.read_entire_file(filename, context.allocator)
	if err == nil {return string(data), true}
	log.errorf("Error loading shader file: %s (Error code: %v)", filename, err)
	return "", false
}