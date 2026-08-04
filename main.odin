package main

import "core:fmt"
import "core:log"
import rl "vendor:raylib"

SCREEN_WIDTH := 1200
SCREEN_HEIGHT := 800

VERTEX_SHADER_PATH :: "shaders/vertexShader.glsl"
FRAGMENT_SHADER_PATH :: "shaders/fragmentShader.glsl"
UPSCALE_SHADER_PATH :: "shaders/biCubicUpscale.glsl"

// clouds are raymarched at this fraction of the scene's native resolution,
// then bicubic-upscaled back up during composite. lower = cheaper raymarch,
// softer result.
CLOUD_RENDER_SCALE: f32 : 0.5

LOC_U_TIME :: 0
LOC_U_RESOLUTION :: 1
LOC_U_NOISE_TEX :: 2
LOC_U_BLUE_NOISE_TEX :: 3
LOC_U_FRAME :: 4
LOC_U_SPHERE_RADIUS :: 5
LOC_U_ABSORPTION :: 6
LOC_U_ANISOTROPY :: 7
LOC_U_SUN_DIR :: 8
LOC_U_SUN_COLOR :: 9
LOC_U_SKY_TOP :: 10
LOC_U_SKY_BOTTOM :: 11
LOC_U_MARCH_SIZE :: 12
LOC_U_DENSITY_SCALE :: 13
LOC_U_MAX_STEPS :: 14
LOC_U_MAX_LIGHT_STEPS :: 15
LOC_U_NOISE_SPEED :: 16
LOC_U_AMBIENT :: 17
LOC_U_POWDER_STRENGTH :: 18
LOC_U_CLOUD_TINT :: 19
LOC_U_SUN_GLOW_EXP :: 20
LOC_U_NOISE_SCALE :: 21

LOC_U_ENABLE_CLOUDS :: 22
LOC_U_ENABLE_ANIMATION :: 23
LOC_U_ENABLE_LIGHT_MARCH :: 24
LOC_U_ENABLE_POWDER :: 25
LOC_U_ENABLE_ANISOTROPY :: 26
LOC_U_ENABLE_SUN_GLOW :: 27
LOC_U_ENABLE_SKY_GRADIENT :: 28
LOC_U_ENABLE_DITHER :: 29
LOC_U_ENABLE_TONEMAP :: 30
LOC_U_LOW_QUALITY_NOISE :: 31

// biCubicUpscale.glsl uses explicit `layout(location = N)` qualifiers, so
// these must match the shader source exactly.
LOC_UPSCALE_TEXTURE :: 0
LOC_UPSCALE_TEXEL_SIZE :: 1
LOC_UPSCALE_FULL_SIZE :: 2

NOISE_TEXTURE_PATH :: "assets/noise.png"
BLUE_NOISE_TEXTURE_PATH :: "assets/blueNoise.png"

PANEL_WIDTH_FRACTION :: 0.26
PANEL_MIN_WIDTH :: 280
PANEL_MAX_WIDTH :: 460
PANEL_MARGIN :: 10
DIVIDER_WIDTH :: 2

PANEL_BG :: rl.Color{22, 22, 26, 255}
DIVIDER_COL :: rl.Color{60, 60, 68, 255}

Cloud_Params :: struct {
	sphere_radius:       f32,
	absorption:          f32,
	anisotropy:          f32,
	sun_dir:             [3]f32,
	sun_color:           [3]f32,
	sky_top:             [3]f32,
	sky_bottom:          [3]f32,
	march_size:          f32,
	density_scale:       f32,
	max_steps:           i32,
	max_light_steps:     i32,
	noise_speed:         f32,
	ambient:             f32,
	powder_strength:     f32,
	cloud_tint:          [3]f32,
	sun_glow_exponent:   f32,
	noise_scale:         f32,

	// --- feature toggles ---
	enable_clouds:       bool,
	enable_animation:    bool,
	enable_light_march:  bool,
	enable_powder:       bool,
	enable_anisotropy:   bool,
	enable_sun_glow:     bool,
	enable_sky_gradient: bool,
	enable_dither:       bool,
	enable_tonemap:      bool,
	low_quality_noise:   bool,
}

default_params :: proc() -> Cloud_Params {
	return Cloud_Params {
		sphere_radius = 1.5,
		absorption = 0.9,
		anisotropy = 0.3,
		sun_dir = {1.0, 0.0, 0.0},
		sun_color = {1.0, 0.5, 0.3},
		sky_top = {0.6, 0.6, 0.80},
		sky_bottom = {0.90, 0.75, 0.90},
		march_size = 0.1,
		density_scale = 1.0,
		max_steps = 100,
		max_light_steps = 6,
		noise_speed = 0.5,
		ambient = 0.09,
		powder_strength = 0.5,
		cloud_tint = {1.0, 1.0, 1.0},
		sun_glow_exponent = 10.0,
		noise_scale = 1.0,
		enable_clouds = true,
		enable_animation = true,
		enable_light_march = true,
		enable_powder = true,
		enable_anisotropy = true,
		enable_sun_glow = true,
		enable_sky_gradient = true,
		enable_dither = true,
		enable_tonemap = false,
		low_quality_noise = false,
	}
}

b2i :: proc(b: bool) -> i32 {
	return b ? 1 : 0
}

// --- layout: scene occupies the left region, panel is docked to the right ---

panel_width :: proc() -> i32 {
	w := i32(f32(SCREEN_WIDTH) * PANEL_WIDTH_FRACTION)
	return clamp(w, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
}

scene_rect :: proc() -> (x, y, w, h: i32) {
	w = max(i32(SCREEN_WIDTH) - panel_width() - PANEL_MARGIN * 2 - DIVIDER_WIDTH, 1)
	h = i32(SCREEN_HEIGHT)
	return 0, 0, w, h
}

// resolution the cloud shader actually raymarches at, derived from the
// full-res scene rect scaled down by CLOUD_RENDER_SCALE.
cloud_target_size :: proc(scene_w, scene_h: i32) -> (w, h: i32) {
	w = max(i32(f32(scene_w) * CLOUD_RENDER_SCALE), 1)
	h = max(i32(f32(scene_h) * CLOUD_RENDER_SCALE), 1)
	return
}

Toggle_Uniform :: struct {
	loc: i32,
	val: ^bool,
}

set_toggle_uniforms :: proc(shader: rl.Shader, p: ^Cloud_Params) {
	toggles := []Toggle_Uniform {
		{LOC_U_ENABLE_CLOUDS, &p.enable_clouds},
		{LOC_U_ENABLE_ANIMATION, &p.enable_animation},
		{LOC_U_ENABLE_LIGHT_MARCH, &p.enable_light_march},
		{LOC_U_ENABLE_POWDER, &p.enable_powder},
		{LOC_U_ENABLE_ANISOTROPY, &p.enable_anisotropy},
		{LOC_U_ENABLE_SUN_GLOW, &p.enable_sun_glow},
		{LOC_U_ENABLE_SKY_GRADIENT, &p.enable_sky_gradient},
		{LOC_U_ENABLE_DITHER, &p.enable_dither},
		{LOC_U_ENABLE_TONEMAP, &p.enable_tonemap},
		{LOC_U_LOW_QUALITY_NOISE, &p.low_quality_noise},
	}
	for t in toggles {
		v := b2i(t.val^)
		rl.SetShaderValue(shader, t.loc, &v, .INT)
	}
}

set_scalar_uniforms :: proc(
	shader: rl.Shader,
	p: ^Cloud_Params,
	resolution: [2]f32,
	time: f32,
	frame_count: i32,
) {
	res := resolution
	t := time
	fc := frame_count
	rl.SetShaderValue(shader, LOC_U_TIME, &t, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_RESOLUTION, &res, .VEC2)
	rl.SetShaderValue(shader, LOC_U_FRAME, &fc, .INT)
	rl.SetShaderValue(shader, LOC_U_SPHERE_RADIUS, &p.sphere_radius, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_ABSORPTION, &p.absorption, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_ANISOTROPY, &p.anisotropy, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_SUN_DIR, &p.sun_dir, .VEC3)
	rl.SetShaderValue(shader, LOC_U_SUN_COLOR, &p.sun_color, .VEC3)
	rl.SetShaderValue(shader, LOC_U_SKY_TOP, &p.sky_top, .VEC3)
	rl.SetShaderValue(shader, LOC_U_SKY_BOTTOM, &p.sky_bottom, .VEC3)
	rl.SetShaderValue(shader, LOC_U_MARCH_SIZE, &p.march_size, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_DENSITY_SCALE, &p.density_scale, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_MAX_STEPS, &p.max_steps, .INT)
	rl.SetShaderValue(shader, LOC_U_MAX_LIGHT_STEPS, &p.max_light_steps, .INT)
	rl.SetShaderValue(shader, LOC_U_NOISE_SPEED, &p.noise_speed, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_AMBIENT, &p.ambient, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_POWDER_STRENGTH, &p.powder_strength, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_CLOUD_TINT, &p.cloud_tint, .VEC3)
	rl.SetShaderValue(shader, LOC_U_SUN_GLOW_EXP, &p.sun_glow_exponent, .FLOAT)
	rl.SetShaderValue(shader, LOC_U_NOISE_SCALE, &p.noise_scale, .FLOAT)
}

// draws `src` (a low-res render texture) into the given full-res destination
// rect using the bicubic upscale shader.
draw_upscaled :: proc(upscale_shader: rl.Shader, src: rl.RenderTexture2D, dest_w, dest_h: i32) {
	texel_size := [2]f32{1.0 / f32(src.texture.width), 1.0 / f32(src.texture.height)}
	full_size := [2]f32{f32(src.texture.width), f32(src.texture.height)}

	rl.BeginShaderMode(upscale_shader)
	rl.SetShaderValue(upscale_shader, LOC_UPSCALE_TEXEL_SIZE, &texel_size, .VEC2)
	rl.SetShaderValue(upscale_shader, LOC_UPSCALE_FULL_SIZE, &full_size, .VEC2)
	// LOC_UPSCALE_TEXTURE (location 0) needs no explicit SetShaderValueTexture
	// call: DrawTexturePro binds `src.texture` to GL texture unit 0, and an
	// unset sampler uniform defaults to unit 0 anyway.
	rl.DrawTexturePro(
		src.texture,
		rl.Rectangle{0, 0, f32(src.texture.width), f32(src.texture.height)},
		rl.Rectangle{0, 0, f32(dest_w), f32(dest_h)},
		rl.Vector2{0, 0},
		0,
		rl.WHITE,
	)
	rl.EndShaderMode()
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

	init_microui()
	defer shutdown_microui()

	state, ok := load_shader_state()
	if !ok {
		log.error("Failed to load initial shader, exiting.")
		return
	}
	defer rl.UnloadShader(state.shader)
	defer rl.UnloadTexture(state.noise_tex)
	defer rl.UnloadTexture(state.blue_noise_tex)

	upscale_shader := rl.LoadShader(nil, UPSCALE_SHADER_PATH)
	if upscale_shader.id == 0 {
		log.error("Failed to load upscale shader, exiting.")
		return
	}
	defer rl.UnloadShader(upscale_shader)

	params := default_params()
	frame_count: i32 = 0

	// clouds raymarch into this low-res target; it gets bicubic-upscaled
	// into the full-res scene area every frame.
	_, _, scene_w, scene_h := scene_rect()
	cloud_w, cloud_h := cloud_target_size(scene_w, scene_h)
	cloud_target := rl.LoadRenderTexture(cloud_w, cloud_h)
	defer rl.UnloadRenderTexture(cloud_target)

	for !rl.WindowShouldClose() {
		// poll the real framebuffer size every frame rather than relying on
		// IsWindowResized(), which can miss the frame a maximize/fullscreen
		// transition happens on (and GetRenderWidth/Height also accounts for
		// HighDPI/Retina scaling, unlike GetScreenWidth/Height).
		SCREEN_WIDTH = int(rl.GetRenderWidth())
		SCREEN_HEIGHT = int(rl.GetRenderHeight())

		if rl.IsKeyPressed(.F11) {
			rl.ToggleFullscreen()
		}
		if rl.IsKeyPressed(.F5) {
			reload_shader(&state)
		}

		// keep the low-res cloud target in sync with the scene region's size
		_, _, want_scene_w, want_scene_h := scene_rect()
		want_cloud_w, want_cloud_h := cloud_target_size(want_scene_w, want_scene_h)
		if want_cloud_w != cloud_target.texture.width ||
		   want_cloud_h != cloud_target.texture.height {
			rl.UnloadRenderTexture(cloud_target)
			cloud_target = rl.LoadRenderTexture(want_cloud_w, want_cloud_h)
		}

		ctx := &ui_state.mu_ctx
		microui_handle_input(ctx)
		mu_begin_and_draw(ctx, &params)

		time := f32(rl.GetTime())
		resolution := [2]f32{f32(cloud_target.texture.width), f32(cloud_target.texture.height)}
		set_scalar_uniforms(state.shader, &params, resolution, time, frame_count)
		set_toggle_uniforms(state.shader, &params)

		// --- pass 1: raymarch clouds at low res into cloud_target ---
		rl.BeginTextureMode(cloud_target)
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(state.shader)
		rl.SetShaderValueTexture(state.shader, state.noise_tex_loc, state.noise_tex)
		rl.SetShaderValueTexture(state.shader, state.blue_noise_tex_loc, state.blue_noise_tex)
		rl.DrawRectangle(0, 0, cloud_target.texture.width, cloud_target.texture.height, rl.WHITE)
		rl.EndShaderMode()
		rl.EndTextureMode()

		// --- pass 2: composite bicubic-upscaled clouds (left) + divider + control panel (right) ---
		rl.BeginDrawing()
		rl.ClearBackground(PANEL_BG)

		draw_upscaled(upscale_shader, cloud_target, want_scene_w, want_scene_h)

		rl.DrawRectangle(want_scene_w, 0, DIVIDER_WIDTH, i32(SCREEN_HEIGHT), DIVIDER_COL)

		rl.DrawText(fmt.ctprint("FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		rl.DrawText("F5: reload shader", 10, 35, 10, rl.WHITE)

		microui_render(ctx)

		rl.EndDrawing()
		frame_count += 1
	}
}
