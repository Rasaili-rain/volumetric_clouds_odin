package main

import "core:c"
import "core:strings"
import "core:unicode/utf8"
import mu "vendor:microui"
import rl "vendor:raylib"

// --- microui/raylib glue (adapted from odin-lang/examples) ---

ui_state := struct {
	mu_ctx:        mu.Context,
	atlas_texture: rl.RenderTexture2D,
}{}

mouse_buttons_map := [mu.Mouse]rl.MouseButton {
	.LEFT   = .LEFT,
	.RIGHT  = .RIGHT,
	.MIDDLE = .MIDDLE,
}

key_map := [mu.Key][2]rl.KeyboardKey {
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
	mu.init(ctx, set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
			cstr := strings.clone_to_cstring(text)
			rl.SetClipboardText(cstr)
			delete(cstr)
			return true
		}, get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
			cstr := rl.GetClipboardText()
			if cstr != nil {
				text = string(cstr)
				ok = true
			}
			return
		})
	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	ui_state.atlas_texture = rl.LoadRenderTexture(
		c.int(mu.DEFAULT_ATLAS_WIDTH),
		c.int(mu.DEFAULT_ATLAS_HEIGHT),
	)
	image := rl.GenImageColor(
		c.int(mu.DEFAULT_ATLAS_WIDTH),
		c.int(mu.DEFAULT_ATLAS_HEIGHT),
		rl.Color{0, 0, 0, 0},
	)
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
			texture = ui_state.atlas_texture.texture,
			source = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint = color,
		)
	}
	to_rl_color :: proc(c: mu.Color) -> rl.Color {return {c.r, c.g, c.b, c.a}}

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
			rl.DrawRectangle(
				cmd.rect.x,
				cmd.rect.y,
				cmd.rect.w,
				cmd.rect.h,
				to_rl_color(cmd.color),
			)
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

dock_rect :: proc() -> mu.Rect {
	return mu.Rect {
		i32(SCREEN_WIDTH) - panel_width() - PANEL_MARGIN,
		PANEL_MARGIN,
		panel_width(),
		i32(SCREEN_HEIGHT) - PANEL_MARGIN * 2,
	}
}

mu_begin_and_draw :: proc(ctx: ^mu.Context, params: ^Cloud_Params) {
	mu.begin(ctx)
	draw_cloud_controls(ctx, params)
	mu.end(ctx)
}

draw_cloud_controls :: proc(ctx: ^mu.Context, p: ^Cloud_Params) {
	rect := dock_rect()

	if mu.window(ctx, "Cloud Parameters", rect) {

		if .ACTIVE in mu.header(ctx, "Toggles", {.EXPANDED}) {
			toggle_col := (panel_width() - PANEL_MARGIN * 2 - 40) / 2
			mu.layout_row(ctx, {toggle_col, toggle_col}, 0)
			toggle(ctx, "Clouds", &p.enable_clouds)
			toggle(ctx, "Animate", &p.enable_animation)
			toggle(ctx, "Self-Shadow", &p.enable_light_march)
			toggle(ctx, "Powder Edges", &p.enable_powder)
			toggle(ctx, "Anisotropy", &p.enable_anisotropy)
			toggle(ctx, "Sun Glow", &p.enable_sun_glow)
			toggle(ctx, "Sky Gradient", &p.enable_sky_gradient)
			toggle(ctx, "Dither", &p.enable_dither)
			toggle(ctx, "Tonemap", &p.enable_tonemap)
			toggle(ctx, "Fast Preview", &p.low_quality_noise)
		}

		mu.layout_row(ctx, {110, -1}, 0)
		mu.label(ctx, "Radius"); real_slider(ctx, &p.sphere_radius, 0.2, 3.0)
		mu.label(ctx, "Absorption"); real_slider(ctx, &p.absorption, 0.0, 3.0)
		mu.label(ctx, "Anisotropy"); real_slider(ctx, &p.anisotropy, -0.99, 0.99)
		mu.label(ctx, "March Size"); real_slider(ctx, &p.march_size, 0.02, 0.3)
		mu.label(ctx, "Density"); real_slider(ctx, &p.density_scale, 0.1, 3.0)
		mu.label(ctx, "NoiseSpeed"); real_slider(ctx, &p.noise_speed, 0.0, 2.0)

		steps_f := f32(p.max_steps)
		mu.label(ctx, "Max Steps"); real_slider(ctx, &steps_f, 10, 100)
		p.max_steps = i32(steps_f)

		light_steps_f := f32(p.max_light_steps)
		mu.label(ctx, "Light Steps"); real_slider(ctx, &light_steps_f, 1, 6)
		p.max_light_steps = i32(light_steps_f)

		if .ACTIVE in mu.header(ctx, "Shading", {.EXPANDED}) {
			mu.layout_row(ctx, {110, -1}, 0)
			mu.label(ctx, "Ambient"); real_slider(ctx, &p.ambient, 0.0, 0.5)
			mu.label(ctx, "Powder"); real_slider(ctx, &p.powder_strength, 0.0, 1.0)
			mu.label(ctx, "Sun Glow"); real_slider(ctx, &p.sun_glow_exponent, 1.0, 64.0)
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
