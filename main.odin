package main

import "core:c"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"
import mu "vendor:microui"

SCREEN_WIDTH := 1200
SCREEN_HEIGHT := 800

VERTEX_SHADER_PATH :: "shaders/vertexShader.glsl"
FRAGMENT_SHADER_PATH :: "shaders/fragmentShader.glsl"


LOC_U_TIME             :: 0
LOC_U_RESOLUTION       :: 1
LOC_U_NOISE_TEX        :: 2
LOC_U_BLUE_NOISE_TEX   :: 3
LOC_U_FRAME            :: 4
LOC_U_SPHERE_RADIUS    :: 5
LOC_U_ABSORPTION       :: 6
LOC_U_ANISOTROPY       :: 7
LOC_U_SUN_DIR          :: 8
LOC_U_SUN_COLOR        :: 9
LOC_U_SKY_TOP          :: 10
LOC_U_SKY_BOTTOM       :: 11
LOC_U_MARCH_SIZE       :: 12
LOC_U_DENSITY_SCALE    :: 13
LOC_U_MAX_STEPS        :: 14
LOC_U_MAX_LIGHT_STEPS  :: 15
LOC_U_NOISE_SPEED      :: 16
LOC_U_AMBIENT          :: 17
LOC_U_POWDER_STRENGTH  :: 18
LOC_U_CLOUD_TINT       :: 19
LOC_U_SUN_GLOW_EXP     :: 20
LOC_U_NOISE_SCALE      :: 21

// --- toggle uniform locations ---
LOC_U_ENABLE_CLOUDS        :: 22
LOC_U_ENABLE_ANIMATION     :: 23
LOC_U_ENABLE_LIGHT_MARCH   :: 24
LOC_U_ENABLE_POWDER        :: 25
LOC_U_ENABLE_ANISOTROPY    :: 26
LOC_U_ENABLE_SUN_GLOW      :: 27
LOC_U_ENABLE_SKY_GRADIENT  :: 28
LOC_U_ENABLE_DITHER        :: 29
LOC_U_ENABLE_TONEMAP       :: 30
LOC_U_LOW_QUALITY_NOISE    :: 31

NOISE_TEXTURE_PATH :: "assets/noise.png"
BLUE_NOISE_TEXTURE_PATH :: "assets/blueNoise.png"

PANEL_WIDTH_FRACTION :: 0.26
PANEL_MIN_WIDTH :: 280
PANEL_MAX_WIDTH :: 460
PANEL_MARGIN :: 10
DIVIDER_WIDTH :: 2

PANEL_BG    :: rl.Color{22, 22, 26, 255}
DIVIDER_COL :: rl.Color{60, 60, 68, 255}

Shader_State :: struct {
	shader:             rl.Shader,
	noise_tex:          rl.Texture2D,
	noise_tex_loc:      i32,
	blue_noise_tex:     rl.Texture2D,
	blue_noise_tex_loc: i32,
}

Cloud_Params :: struct {
	sphere_radius:     f32,
	absorption:        f32,
	anisotropy:        f32,
	sun_dir:           [3]f32,
	sun_color:         [3]f32,
	sky_top:           [3]f32,
	sky_bottom:        [3]f32,
	march_size:        f32,
	density_scale:     f32,
	max_steps:         i32,
	max_light_steps:   i32,
	noise_speed:       f32,
	ambient:           f32,
	powder_strength:   f32,
	cloud_tint:        [3]f32,
	sun_glow_exponent: f32,
	noise_scale:       f32,

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
	return Cloud_Params{
		sphere_radius     = 1.5,
		absorption        = 0.9,
		anisotropy        = 0.3,
		sun_dir           = {1.0, 0.0, 0.0},
		sun_color         = {1.0, 0.5, 0.3},
		sky_top           = {0.6, 0.6, 0.80},
		sky_bottom        = {0.90, 0.75, 0.90},
		march_size        = 0.1,
		density_scale     = 1.0,
		max_steps         = 100,
		max_light_steps   = 6,
		noise_speed       = 0.5,
		ambient           = 0.09,
		powder_strength   = 0.5,
		cloud_tint        = {1.0, 1.0, 1.0},
		sun_glow_exponent = 10.0,
		noise_scale       = 1.0,

		enable_clouds       = true,
		enable_animation    = true,
		enable_light_march  = true,
		enable_powder       = true,
		enable_anisotropy   = true,
		enable_sun_glow     = true,
		enable_sky_gradient = true,
		enable_dither       = true,
		enable_tonemap      = false,
		low_quality_noise   = false,
	}
}

b2i :: proc(b: bool) -> i32 {
	return b ? 1 : 0
}

// --- microui/raylib glue (adapted from odin-lang/examples) ---

ui_state := struct {
	mu_ctx:        mu.Context,
	atlas_texture: rl.RenderTexture2D,
}{}

mouse_buttons_map := [mu.Mouse]rl.MouseButton{
	.LEFT   = .LEFT,
	.RIGHT  = .RIGHT,
	.MIDDLE = .MIDDLE,
}

key_map := [mu.Key][2]rl.KeyboardKey{
	.SHIFT     = {.LEFT_SHIFT, .RIGHT_SHIFT},
	.CTRL      = {.LEFT_CONTROL, .RIGHT_CONTROL},
	.ALT       = {.LEFT_ALT, .RIGHT_ALT},
	.BACKSPACE = {.BACKSPACE, .KEY_NULL},
	.DELETE    = {.DELETE, .KEY_NULL},
	.RETURN    = {.ENTER, .KP_ENTER},
	.LEFT      = {.LEFT, .KEY_NULL},
	.RIGHT     = {.RIGHT, .KEY_NULL},
	.HOME      = {.HOME, .KEY_NULL},
	.END       = {.END, .KEY_NULL},
	.A         = {.A, .KEY_NULL},
	.X         = {.X, .KEY_NULL},
	.C         = {.C, .KEY_NULL},
	.V         = {.V, .KEY_NULL},
}

init_microui :: proc() {
	ctx := &ui_state.mu_ctx
	mu.init(ctx,
		set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
			cstr := strings.clone_to_cstring(text)
			rl.SetClipboardText(cstr)
			delete(cstr)
			return true
		},
		get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
			cstr := rl.GetClipboardText()
			if cstr != nil {
				text = string(cstr)
				ok = true
			}
			return
		},
	)
	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	ui_state.atlas_texture = rl.LoadRenderTexture(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT))
	image := rl.GenImageColor(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})
	defer rl.UnloadImage(image)
	for alpha, i in mu.default_atlas_alpha {
		x := i % mu.DEFAULT_ATLAS_WIDTH
		y := i / mu.DEFAULT_ATLAS_WIDTH
		rl.ImageDrawPixel(&image, c.int(x), c.int(y), rl.Color{255, 255, 255, alpha})
	}
	rl.UpdateTexture(ui_state.atlas_texture.texture, rl.LoadImageColors(image))
}

shutdown_microui :: proc() {
	rl.UnloadRenderTexture(ui_state.atlas_texture)
}

microui_handle_input :: proc(ctx: ^mu.Context) {
	mouse_pos := rl.GetMousePosition()
	mouse_x, mouse_y := i32(mouse_pos.x), i32(mouse_pos.y)
	mu.input_mouse_move(ctx, mouse_x, mouse_y)

	wheel := rl.GetMouseWheelMoveV()
	mu.input_scroll(ctx, i32(wheel.x) * 30, i32(wheel.y) * -30)

	for button_rl, button_mu in mouse_buttons_map {
		switch {
		case rl.IsMouseButtonPressed(button_rl):
			mu.input_mouse_down(ctx, mouse_x, mouse_y, button_mu)
		case rl.IsMouseButtonReleased(button_rl):
			mu.input_mouse_up(ctx, mouse_x, mouse_y, button_mu)
		}
	}

	for keys_rl, key_mu in key_map {
		for key_rl in keys_rl {
			switch {
			case key_rl == .KEY_NULL:
			case rl.IsKeyPressed(key_rl), rl.IsKeyPressedRepeat(key_rl):
				mu.input_key_down(ctx, key_mu)
			case rl.IsKeyReleased(key_rl):
				mu.input_key_up(ctx, key_mu)
			}
		}
	}

	buf: [512]byte
	n: int
	for n < len(buf) {
		ch := rl.GetCharPressed()
		if ch == 0 do break
		b, w := utf8.encode_rune(ch)
		n += copy(buf[n:], b[:w])
	}
	mu.input_text(ctx, string(buf[:n]))
}

// Draws microui commands straight onto the currently bound framebuffer
// (call this between BeginDrawing/EndDrawing, after your shader pass).
microui_render :: proc(ctx: ^mu.Context) {
	render_glyph :: proc(dst: ^rl.Rectangle, src: mu.Rect, color: rl.Color) {
		dst.width = f32(src.w)
		dst.height = f32(src.h)
		rl.DrawTextureRec(
			texture  = ui_state.atlas_texture.texture,
			source   = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint     = color,
		)
	}
	to_rl_color :: proc(c: mu.Color) -> rl.Color { return {c.r, c.g, c.b, c.a} }

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := rl.Rectangle{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str {
				if ch & 0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_glyph(&dst, src, to_rl_color(cmd.color))
					dst.x += dst.width
				}
			}
		case ^mu.Command_Rect:
			rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, to_rl_color(cmd.color))
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			dst := rl.Rectangle{f32(x), f32(y), 0, 0}
			render_glyph(&dst, src, to_rl_color(cmd.color))
		case ^mu.Command_Clip:
			rl.BeginScissorMode(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
	rl.EndScissorMode()
}

// f32 slider helper, mirrors the u8_slider pattern from the official demo
real_slider :: proc(ctx: ^mu.Context, val: ^f32, lo, hi: f32) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))
	tmp := mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.2f", {.ALIGN_CENTER})
	val^ = f32(tmp)
	mu.pop_id(ctx)
	return
}

// checkbox helper so each toggle gets a stable id (bool addresses can alias otherwise)
toggle :: proc(ctx: ^mu.Context, label: string, val: ^bool) {
	mu.push_id(ctx, uintptr(val))
	mu.checkbox(ctx, label, val)
	mu.pop_id(ctx)
}

// --- layout: scene occupies the left region, panel is docked to the right ---
// both are derived from the *current* window size every call, so they always
// agree with each other and with whatever just got resized.

panel_width :: proc() -> i32 {
	w := i32(f32(SCREEN_WIDTH) * PANEL_WIDTH_FRACTION)
	return clamp(w, PANEL_MIN_WIDTH, PANEL_MAX_WIDTH)
}

scene_rect :: proc() -> (x, y, w, h: i32) {
	w = max(i32(SCREEN_WIDTH) - panel_width() - PANEL_MARGIN * 2 - DIVIDER_WIDTH, 1)
	h = i32(SCREEN_HEIGHT)
	return 0, 0, w, h
}

dock_rect :: proc() -> mu.Rect {
	return mu.Rect{
		i32(SCREEN_WIDTH) - panel_width() - PANEL_MARGIN,
		PANEL_MARGIN,
		panel_width(),
		i32(SCREEN_HEIGHT) - PANEL_MARGIN * 2,
	}
}

draw_cloud_controls :: proc(ctx: ^mu.Context, p: ^Cloud_Params) {
	rect := dock_rect()

	if mu.window(ctx, "Cloud Parameters", rect) {

		if .ACTIVE in mu.header(ctx, "Toggles", {.EXPANDED}) {
			toggle_col := (panel_width() - PANEL_MARGIN * 2 - 40) / 2
			mu.layout_row(ctx, {toggle_col, toggle_col}, 0)
			toggle(ctx, "Clouds",       &p.enable_clouds)
			toggle(ctx, "Animate",      &p.enable_animation)
			toggle(ctx, "Self-Shadow",  &p.enable_light_march)
			toggle(ctx, "Powder Edges", &p.enable_powder)
			toggle(ctx, "Anisotropy",   &p.enable_anisotropy)
			toggle(ctx, "Sun Glow",     &p.enable_sun_glow)
			toggle(ctx, "Sky Gradient", &p.enable_sky_gradient)
			toggle(ctx, "Dither",       &p.enable_dither)
			toggle(ctx, "Tonemap",      &p.enable_tonemap)
			toggle(ctx, "Fast Preview", &p.low_quality_noise)
		}

		mu.layout_row(ctx, {110, -1}, 0)
		mu.label(ctx, "Radius");     real_slider(ctx, &p.sphere_radius, 0.2, 3.0)
		mu.label(ctx, "Absorption"); real_slider(ctx, &p.absorption, 0.0, 3.0)
		mu.label(ctx, "Anisotropy"); real_slider(ctx, &p.anisotropy, -0.99, 0.99)
		mu.label(ctx, "March Size"); real_slider(ctx, &p.march_size, 0.02, 0.3)
		mu.label(ctx, "Density");    real_slider(ctx, &p.density_scale, 0.1, 3.0)
		mu.label(ctx, "NoiseSpeed"); real_slider(ctx, &p.noise_speed, 0.0, 2.0)

		steps_f := f32(p.max_steps)
		mu.label(ctx, "Max Steps"); real_slider(ctx, &steps_f, 10, 100)
		p.max_steps = i32(steps_f)

		light_steps_f := f32(p.max_light_steps)
		mu.label(ctx, "Light Steps"); real_slider(ctx, &light_steps_f, 1, 6)
		p.max_light_steps = i32(light_steps_f)

		if .ACTIVE in mu.header(ctx, "Shading", {.EXPANDED}) {
			mu.layout_row(ctx, {110, -1}, 0)
			mu.label(ctx, "Ambient");     real_slider(ctx, &p.ambient, 0.0, 0.5)
			mu.label(ctx, "Powder");      real_slider(ctx, &p.powder_strength, 0.0, 1.0)
			mu.label(ctx, "Sun Glow");    real_slider(ctx, &p.sun_glow_exponent, 1.0, 64.0)
			mu.label(ctx, "Noise Scale"); real_slider(ctx, &p.noise_scale, 0.2, 3.0)

			mu.layout_row(ctx, {50, -1}, 0)
			mu.label(ctx, "Tint R"); real_slider(ctx, &p.cloud_tint.r, 0, 2)
			mu.label(ctx, "Tint G"); real_slider(ctx, &p.cloud_tint.g, 0, 2)
			mu.label(ctx, "Tint B"); real_slider(ctx, &p.cloud_tint.b, 0, 2)
		}

		if .ACTIVE in mu.header(ctx, "Sun Direction") {
			mu.layout_row(ctx, {50, -1}, 0)
			mu.label(ctx, "X"); real_slider(ctx, &p.sun_dir.x, -1, 1)
			mu.label(ctx, "Y"); real_slider(ctx, &p.sun_dir.y, -1, 1)
			mu.label(ctx, "Z"); real_slider(ctx, &p.sun_dir.z, -1, 1)
		}
		if .ACTIVE in mu.header(ctx, "Sun Color") {
			mu.layout_row(ctx, {50, -1}, 0)
			mu.label(ctx, "R"); real_slider(ctx, &p.sun_color.r, 0, 1)
			mu.label(ctx, "G"); real_slider(ctx, &p.sun_color.g, 0, 1)
			mu.label(ctx, "B"); real_slider(ctx, &p.sun_color.b, 0, 1)
		}
		if .ACTIVE in mu.header(ctx, "Sky Colors") {
			mu.layout_row(ctx, {50, -1}, 0)
			mu.label(ctx, "Top R"); real_slider(ctx, &p.sky_top.r, 0, 1)
			mu.label(ctx, "Top G"); real_slider(ctx, &p.sky_top.g, 0, 1)
			mu.label(ctx, "Top B"); real_slider(ctx, &p.sky_top.b, 0, 1)
			mu.label(ctx, "Bot R"); real_slider(ctx, &p.sky_bottom.r, 0, 1)
			mu.label(ctx, "Bot G"); real_slider(ctx, &p.sky_bottom.g, 0, 1)
			mu.label(ctx, "Bot B"); real_slider(ctx, &p.sky_bottom.b, 0, 1)
		}

		mu.layout_row(ctx, {-1}, 0)
		if .SUBMIT in mu.button(ctx, "Reset to Defaults") {
			p^ = default_params()
		}
	}
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

	params := default_params()
	frame_count: i32 = 0

	// off-screen target the cloud shader renders into; sized to the left (scene) region only
	_, _, scene_w, scene_h := scene_rect()
	scene_target := rl.LoadRenderTexture(scene_w, scene_h)
	defer rl.UnloadRenderTexture(scene_target)

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

		// keep the render target in sync with the scene region's size
		_, _, want_w, want_h := scene_rect()
		if want_w != scene_target.texture.width || want_h != scene_target.texture.height {
			rl.UnloadRenderTexture(scene_target)
			scene_target = rl.LoadRenderTexture(want_w, want_h)
		}

		ctx := &ui_state.mu_ctx
		microui_handle_input(ctx)
		mu.begin(ctx)
		draw_cloud_controls(ctx, &params)
		mu.end(ctx)

		time := f32(rl.GetTime())
		resolution := [2]f32{f32(scene_target.texture.width), f32(scene_target.texture.height)}
		rl.SetShaderValue(state.shader, LOC_U_TIME, &time, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_RESOLUTION, &resolution, .VEC2)
		rl.SetShaderValue(state.shader, LOC_U_FRAME, &frame_count, .INT)
		rl.SetShaderValue(state.shader, LOC_U_SPHERE_RADIUS, &params.sphere_radius, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_ABSORPTION, &params.absorption, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_ANISOTROPY, &params.anisotropy, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_SUN_DIR, &params.sun_dir, .VEC3)
		rl.SetShaderValue(state.shader, LOC_U_SUN_COLOR, &params.sun_color, .VEC3)
		rl.SetShaderValue(state.shader, LOC_U_SKY_TOP, &params.sky_top, .VEC3)
		rl.SetShaderValue(state.shader, LOC_U_SKY_BOTTOM, &params.sky_bottom, .VEC3)
		rl.SetShaderValue(state.shader, LOC_U_MARCH_SIZE, &params.march_size, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_DENSITY_SCALE, &params.density_scale, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_MAX_STEPS, &params.max_steps, .INT)
		rl.SetShaderValue(state.shader, LOC_U_MAX_LIGHT_STEPS, &params.max_light_steps, .INT)
		rl.SetShaderValue(state.shader, LOC_U_NOISE_SPEED, &params.noise_speed, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_AMBIENT, &params.ambient, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_POWDER_STRENGTH, &params.powder_strength, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_CLOUD_TINT, &params.cloud_tint, .VEC3)
		rl.SetShaderValue(state.shader, LOC_U_SUN_GLOW_EXP, &params.sun_glow_exponent, .FLOAT)
		rl.SetShaderValue(state.shader, LOC_U_NOISE_SCALE, &params.noise_scale, .FLOAT)

		enable_clouds       := b2i(params.enable_clouds)
		enable_animation    := b2i(params.enable_animation)
		enable_light_march  := b2i(params.enable_light_march)
		enable_powder       := b2i(params.enable_powder)
		enable_anisotropy   := b2i(params.enable_anisotropy)
		enable_sun_glow     := b2i(params.enable_sun_glow)
		enable_sky_gradient := b2i(params.enable_sky_gradient)
		enable_dither       := b2i(params.enable_dither)
		enable_tonemap      := b2i(params.enable_tonemap)
		low_quality_noise   := b2i(params.low_quality_noise)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_CLOUDS, &enable_clouds, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_ANIMATION, &enable_animation, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_LIGHT_MARCH, &enable_light_march, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_POWDER, &enable_powder, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_ANISOTROPY, &enable_anisotropy, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_SUN_GLOW, &enable_sun_glow, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_SKY_GRADIENT, &enable_sky_gradient, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_DITHER, &enable_dither, .INT)
		rl.SetShaderValue(state.shader, LOC_U_ENABLE_TONEMAP, &enable_tonemap, .INT)
		rl.SetShaderValue(state.shader, LOC_U_LOW_QUALITY_NOISE, &low_quality_noise, .INT)

		// --- pass 1: render the cloud scene into its own texture (left region only) ---
		rl.BeginTextureMode(scene_target)
		rl.ClearBackground(rl.BLACK)
		rl.BeginShaderMode(state.shader)
		rl.SetShaderValueTexture(state.shader, state.noise_tex_loc, state.noise_tex)
		rl.SetShaderValueTexture(state.shader, state.blue_noise_tex_loc, state.blue_noise_tex)
		rl.DrawRectangle(0, 0, scene_target.texture.width, scene_target.texture.height, rl.WHITE)
		rl.EndShaderMode()
		rl.EndTextureMode()

		// --- pass 2: composite scene (left) + divider + control panel (right) ---
		rl.BeginDrawing()
		rl.ClearBackground(PANEL_BG)

		// render textures are stored bottom-up, flip on draw
		rl.DrawTextureRec(
			scene_target.texture,
			rl.Rectangle{0, 0, f32(scene_target.texture.width), -f32(scene_target.texture.height)},
			rl.Vector2{0, 0},
			rl.WHITE,
		)

		rl.DrawRectangle(scene_target.texture.width, 0, DIVIDER_WIDTH, i32(SCREEN_HEIGHT), DIVIDER_COL)

		rl.DrawText(fmt.ctprint("FPS:", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		rl.DrawText("F5: reload shader", 10, 35, 10, rl.WHITE)

		microui_render(ctx)

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

	state = Shader_State{
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
