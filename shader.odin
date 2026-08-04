package main

import "core:log"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

Shader_State :: struct {
	shader:             rl.Shader,
	noise_tex:          rl.Texture2D,
	noise_tex_loc:      i32,
	blue_noise_tex:     rl.Texture2D,
	blue_noise_tex_loc: i32,
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
