// Copyright (C) 2025  Davorin Šego

// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.

// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
// more details.

// You should have received a copy of the GNU General Public License along
// with this program.  If not, see <http://www.gnu.org/licenses/>.


package app

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "../core"

shadow_data := #load("../assets/images/shadow.2x.png")

// Bloom for the strobe glow, rendered at a fraction of the strobe size since it gets blurred anyway
BLOOM_DOWNSCALE :: 2
BLOOM_TAP_SPACING :: 1.5 // blur taps spaced apart for a wider glow at the same cost
BLOOM_ITERATIONS :: 2
BLOOM_STRENGTH :: 0.2

StrobeDisplay :: struct {
    // GL Shader
    strobe_shader:         rl.Shader,
    inner_shadow_shader:   rl.Shader,

    // this is just a dummy texture to get the texture coordinates working right in the fragment shader
    texture:               rl.Texture,
    shadow_tex:            rl.Texture,
    texture_width:         i32,
    texture_height:        i32,
    position:              [2]f32,
    colors:                [2]rl.Color,
    background:            rl.Color,

    // strobe shader uniform locations
    color_a_loc:           i32,
    color_b_loc:           i32,
    time_stretch_loc:      i32,
    period_count_loc:      i32,
    phase_loc:             i32,
    phase_step_loc:        i32,
    motion_blur_loc:       i32,
    glow_loc:              i32,
    lamp_spread_loc:       i32,
    glow_color_loc:        i32,
    glow_exposure_loc:     i32,
    glow_saturation_loc:   i32,
    amp_loc:               i32,
    visibility_loc:        i32,
    norm_freq_loc:         i32,
    bounding_rect_loc:     i32,
    curvature_radius_loc:  i32,
    min_radius_loc:        i32,
    max_radius_loc:        i32,
    band_height_loc:       i32,
    err_cents_loc:         i32,
    strobe_blur_loc:       i32,
    display_type:          StrobeDisplayType,

    // bloom for the strobe glow, the strobe is rendered into scene_rt and blurred through bloom_rt
    bloom_shader:          rl.Shader,
    bloom_mode_loc:        i32,
    bloom_texel_step_loc:  i32,
    scene_rt:              rl.RenderTexture2D,
    bloom_rt:              [2]rl.RenderTexture2D,
    glow_scale:            f32, // DPI scale the render targets were created for

    // shadow shader uniform locations
    shadow_dimensions_loc: i32,

    // per band stripe sharpness and visibility, smoothed so they don't flicker, see update_band_look
    band_amp:              [core.MAX_BANDS]f32,
    band_visibility:       [core.MAX_BANDS]f32,
}


init_strobe_display :: proc(
    position: [2]f32,
    size: [2]i32,
    colors: [2]u32,
    background: u32,
    display_type: StrobeDisplayType,
) -> (
    self: StrobeDisplay,
) {
    self.texture_width = i32(size.x)
    self.texture_height = i32(size.y)
    self.position = position
    self.colors = {rl.GetColor(colors.x), rl.GetColor(colors.y)}
    self.background = rl.GetColor(background)

    // We need this to draw the fragment shader
    texture_image := rl.GenImageColor(
        self.texture_width,
        self.texture_height,
        rl.Color{255, 0, 0, 255},
    )
    self.texture = rl.LoadTextureFromImage(texture_image)
    rl.UnloadImage(texture_image)

    {
        frag_shader_data := #load("../shaders/strobe-shader.frag")
        self.strobe_shader = rl.LoadShaderFromMemory(nil, cstring(&frag_shader_data[0]))
    }

    // Get uniform locations
    self.color_a_loc = rl.GetShaderLocation(self.strobe_shader, "color_a")
    self.color_b_loc = rl.GetShaderLocation(self.strobe_shader, "color_b")
    self.time_stretch_loc = rl.GetShaderLocation(self.strobe_shader, "time_stretch")
    self.phase_loc = rl.GetShaderLocation(self.strobe_shader, "phase")
    self.phase_step_loc = rl.GetShaderLocation(self.strobe_shader, "phase_step")
    self.motion_blur_loc = rl.GetShaderLocation(self.strobe_shader, "motion_blur")
    self.glow_loc = rl.GetShaderLocation(self.strobe_shader, "glow")
    self.lamp_spread_loc = rl.GetShaderLocation(self.strobe_shader, "lamp_spread")
    self.glow_color_loc = rl.GetShaderLocation(self.strobe_shader, "glow_color")
    self.glow_exposure_loc = rl.GetShaderLocation(self.strobe_shader, "glow_exposure")
    self.glow_saturation_loc = rl.GetShaderLocation(self.strobe_shader, "glow_saturation")
    self.amp_loc = rl.GetShaderLocation(self.strobe_shader, "amp")
    self.visibility_loc = rl.GetShaderLocation(self.strobe_shader, "visibility")
    self.norm_freq_loc = rl.GetShaderLocation(self.strobe_shader, "norm_freq")
    self.bounding_rect_loc = rl.GetShaderLocation(self.strobe_shader, "bounding_rect")
    self.curvature_radius_loc = rl.GetShaderLocation(self.strobe_shader, "curvature_radius")
    self.band_height_loc = rl.GetShaderLocation(self.strobe_shader, "band_height")
    self.err_cents_loc = rl.GetShaderLocation(self.strobe_shader, "err_cents")
    self.period_count_loc = rl.GetShaderLocation(self.strobe_shader, "period_count")
    self.min_radius_loc = rl.GetShaderLocation(self.strobe_shader, "min_radius")
    self.max_radius_loc = rl.GetShaderLocation(self.strobe_shader, "max_radius")
    self.strobe_blur_loc = rl.GetShaderLocation(self.strobe_shader, "strobe_blur")
    self.display_type = display_type

    {
        frag_shader_data := #load("../shaders/bloom.frag")
        self.bloom_shader = rl.LoadShaderFromMemory(nil, cstring(&frag_shader_data[0]))
    }
    self.bloom_mode_loc = rl.GetShaderLocation(self.bloom_shader, "mode")
    self.bloom_texel_step_loc = rl.GetShaderLocation(self.bloom_shader, "texel_step")

    // Load shadow texture
    {
        image := rl.LoadImageFromMemory(".png", raw_data(shadow_data), i32(len(shadow_data)))
        defer rl.UnloadImage(image)
        self.shadow_tex = rl.LoadTextureFromImage(image)
    }

    return
}

setup_strobe_display :: proc(self: ^StrobeDisplay, display_type: StrobeDisplayType) {
    self.display_type = display_type
}

destroy_strobe_display :: proc(self: ^StrobeDisplay) {
    rl.UnloadShader(self.strobe_shader)
    rl.UnloadShader(self.inner_shadow_shader)
    rl.UnloadTexture(self.texture)
    rl.UnloadTexture(self.shadow_tex)
    rl.UnloadShader(self.bloom_shader)
    unload_glow_targets(self)
}

@(private)
unload_glow_targets :: proc(self: ^StrobeDisplay) {
    if self.glow_scale == 0 do return
    rl.UnloadRenderTexture(self.scene_rt)
    for rt in self.bloom_rt {
        rl.UnloadRenderTexture(rt)
    }
    self.glow_scale = 0
}

// (Re)create the glow render targets, the scene is rendered at the display's DPI scale to stay sharp
@(private)
ensure_glow_targets :: proc(self: ^StrobeDisplay) {
    scale := rl.GetWindowScaleDPI().x
    if scale == self.glow_scale do return

    unload_glow_targets(self)

    self.scene_rt = rl.LoadRenderTexture(i32(STROBE_WIDTH * scale), i32(STROBE_HEIGHT * scale))
    rl.SetTextureFilter(self.scene_rt.texture, .BILINEAR)
    for &rt in self.bloom_rt {
        rt = rl.LoadRenderTexture(STROBE_WIDTH / BLOOM_DOWNSCALE, STROBE_HEIGHT / BLOOM_DOWNSCALE)
        rl.SetTextureFilter(rt.texture, .BILINEAR)
    }
    self.glow_scale = scale
}

// Render textures are stored upside down, the negative source height flips them back
@(private)
draw_render_texture :: proc(rt: rl.RenderTexture2D, dest: rl.Rectangle, tint := rl.WHITE) {
    source := rl.Rectangle{0, 0, f32(rt.texture.width), -f32(rt.texture.height)}
    rl.DrawTexturePro(rt.texture, source, dest, {0, 0}, 0, tint)
}

// Overwrite the destination instead of alpha blending, the render targets carry no meaningful alpha
@(private)
begin_replace_blend :: proc() {
    rlgl.SetBlendFactors(rlgl.ONE, rlgl.ZERO, rlgl.FUNC_ADD)
    rl.BeginBlendMode(.CUSTOM)
}

// Separable gaussian blur, ping-pongs between the two targets and ends up in rts[0]
@(private)
blur_render_targets :: proc(
    self: ^StrobeDisplay,
    rts: [2]rl.RenderTexture2D,
    iterations: int,
    tap_spacing: f32,
) {
    w := f32(rts[0].texture.width)
    h := f32(rts[0].texture.height)
    dest := rl.Rectangle{0, 0, w, h}

    mode: i32 = 1
    rl.SetShaderValue(self.bloom_shader, self.bloom_mode_loc, &mode, .INT)
    for _ in 0 ..< iterations {
        texel_step := [2]f32{tap_spacing / w, 0}
        rl.SetShaderValue(self.bloom_shader, self.bloom_texel_step_loc, &texel_step, .VEC2)
        rl.BeginTextureMode(rts[1])
        draw_render_texture(rts[0], dest)
        rl.EndTextureMode()

        texel_step = {0, tap_spacing / h}
        rl.SetShaderValue(self.bloom_shader, self.bloom_texel_step_loc, &texel_step, .VEC2)
        rl.BeginTextureMode(rts[0])
        draw_render_texture(rts[1], dest)
        rl.EndTextureMode()
    }
}

// Lift the background a little, as if some lamp light scatters behind the whole disc.
// Based on the darkest stripe, the dark stripes of the outer band away from the hotspot,
// mirrors the light model in the strobe shader.
@(private)
glow_background :: proc(background: rl.Color, glow: GlowParams) -> rl.Color {
    DARK_TRANSMISSION :: 0.3
    MIN_LAMP :: 0.6
    BACKGROUND_LIFT :: 0.25

    glow_color := rl.ColorNormalize(rl.GetColor(glow.color)).rgb
    filter := glow_color / max(glow_color.r, glow_color.g, glow_color.b, 0.001)
    filter *= filter

    darkest: [3]f32
    for c, i in filter {
        darkest[i] = 1 - math.exp(-DARK_TRANSMISSION * MIN_LAMP * glow.exposure * c)
    }

    luma := darkest.r * 0.299 + darkest.g * 0.587 + darkest.b * 0.114
    darkest = linalg.lerp([3]f32{luma, luma, luma}, darkest, glow.saturation)

    base := rl.ColorNormalize(background).rgb
    lifted := linalg.min(base + BACKGROUND_LIFT * darkest, 1)
    return rl.ColorFromNormalized({lifted.r, lifted.g, lifted.b, 1})
}

@(private)
render_bloom :: proc(self: ^StrobeDisplay) {
    begin_replace_blend()
    defer rl.EndBlendMode()
    rl.BeginShaderMode(self.bloom_shader)
    defer rl.EndShaderMode()

    // Downsample and keep the bright parts
    mode: i32 = 0
    texel_step := [2]f32{1.0 / f32(self.scene_rt.texture.width), 1.0 / f32(self.scene_rt.texture.height)}
    rl.SetShaderValue(self.bloom_shader, self.bloom_mode_loc, &mode, .INT)
    rl.SetShaderValue(self.bloom_shader, self.bloom_texel_step_loc, &texel_step, .VEC2)
    rl.BeginTextureMode(self.bloom_rt[0])
    draw_render_texture(
        self.scene_rt,
        {0, 0, f32(self.bloom_rt[0].texture.width), f32(self.bloom_rt[0].texture.height)},
    )
    rl.EndTextureMode()

    blur_render_targets(self, self.bloom_rt, BLOOM_ITERATIONS, BLOOM_TAP_SPACING)
}

set_display_type :: proc(self: ^StrobeDisplay, display_type: StrobeDisplayType) {
    self.display_type = display_type
}

set_strobe_colors :: proc(self: ^StrobeDisplay, colors: [2]u32) {
    self.colors = {rl.GetColor(colors.x), rl.GetColor(colors.y)}
}

draw_strobe_display :: proc(
    self: ^StrobeDisplay,
    phase_info: ^core.PhaseComparator,
    out_of_range: bool,
    config: ^Config,
) {

    curvature_radius: f32
    band_height: f32
    period_count: f32


    switch self.display_type {
    case .SPINNING_WHEEL:
        curvature_radius = 90.0
        band_height = 26.0
        period_count = 4.0 // how many strobe periods to fit in a circle
    case .CURVED_TRACKS:
        curvature_radius = 440.0
        band_height = 66.0
        if len(phase_info.bands) > 3 {
            band_height = 50.0
        }
        period_count = 12.0
    }

    rl.SetShaderValue(
        self.strobe_shader,
        self.band_height_loc,
        &band_height,
        rl.ShaderUniformDataType.FLOAT,
    )
    strobe_blur := int(config.strobe_blur)
    rl.SetShaderValue(
        self.strobe_shader,
        self.strobe_blur_loc,
        &strobe_blur,
        rl.ShaderUniformDataType.INT,
    )

    motion_blur := i32(config.motion_blur)
    rl.SetShaderValue(
        self.strobe_shader,
        self.motion_blur_loc,
        &motion_blur,
        rl.ShaderUniformDataType.INT,
    )

    glow_enabled := config.strobe_glow != .OFF
    glow_params := GLOW_PRESETS[config.strobe_glow]

    glow := i32(glow_enabled)
    rl.SetShaderValue(self.strobe_shader, self.glow_loc, &glow, rl.ShaderUniformDataType.INT)

    // The wheel is lit evenly all around, the tracks only show the top of the disc
    lamp_spread: f32 = 1000.0 if self.display_type == .SPINNING_WHEEL else 0.45
    rl.SetShaderValue(
        self.strobe_shader,
        self.lamp_spread_loc,
        &lamp_spread,
        rl.ShaderUniformDataType.FLOAT,
    )

    glow_color := rl.ColorNormalize(rl.GetColor(glow_params.color))
    rl.SetShaderValue(
        self.strobe_shader,
        self.glow_color_loc,
        raw_data(glow_color[:]),
        rl.ShaderUniformDataType.VEC3,
    )

    rl.SetShaderValue(
        self.strobe_shader,
        self.glow_exposure_loc,
        &glow_params.exposure,
        rl.ShaderUniformDataType.FLOAT,
    )
    rl.SetShaderValue(
        self.strobe_shader,
        self.glow_saturation_loc,
        &glow_params.saturation,
        rl.ShaderUniformDataType.FLOAT,
    )

    n_color_a := rl.ColorNormalize(self.colors.x)
    rl.SetShaderValue(
        self.strobe_shader,
        self.color_a_loc,
        raw_data(n_color_a[:]),
        rl.ShaderUniformDataType.VEC3,
    )

    n_color_b := rl.ColorNormalize(self.colors.y)
    rl.SetShaderValue(
        self.strobe_shader,
        self.color_b_loc,
        raw_data(n_color_b[:]),
        rl.ShaderUniformDataType.VEC3,
    )

    // most inner radius
    min_radius := curvature_radius - band_height

    // most outer radius
    max_radius := curvature_radius + band_height * f32(len(phase_info.bands) - 1)

    rl.SetShaderValue(
        self.strobe_shader,
        self.min_radius_loc,
        &min_radius,
        rl.ShaderUniformDataType.FLOAT,
    )

    rl.SetShaderValue(
        self.strobe_shader,
        self.max_radius_loc,
        &max_radius,
        rl.ShaderUniformDataType.FLOAT,
    )

    y := self.position.y
    if self.display_type == .CURVED_TRACKS {
        y += 32
    }

    strobe_rect := rl.Rectangle{self.position.x, self.position.y, STROBE_WIDTH, STROBE_HEIGHT}

    if glow_enabled {
        // Render the strobe offscreen so the bright parts can bloom over the surroundings
        ensure_glow_targets(self)

        rl.BeginTextureMode(self.scene_rt)
        rl.ClearBackground(
            glow_background(self.background, glow_params),
        )
        rl.BeginMode2D(rl.Camera2D{target = self.position, zoom = self.glow_scale})
        draw_strobe_bands(self, phase_info, config, y, curvature_radius, band_height, period_count)
        rl.EndMode2D()
        rl.EndTextureMode()

        render_bloom(self)
    }

    rl.BeginScissorMode(0, 0, STROBE_WIDTH, STROBE_HEIGHT)
    defer rl.EndScissorMode()

    if glow_enabled {
        begin_replace_blend()
        draw_render_texture(self.scene_rt, strobe_rect)
        rl.EndBlendMode()

        // Add the bloom on top, the light spills into the gaps and the dark background
        rlgl.SetBlendFactors(rlgl.ONE, rlgl.ONE, rlgl.FUNC_ADD)
        rl.BeginBlendMode(.CUSTOM)
        bloom_strength: f32 = BLOOM_STRENGTH
        strength := u8(bloom_strength * 255)
        draw_render_texture(self.bloom_rt[0], strobe_rect, {strength, strength, strength, 255})
        rl.EndBlendMode()
    } else {
        rl.DrawRectangleV(self.position, {f32(self.texture_width), STROBE_HEIGHT}, self.background)
        draw_strobe_bands(self, phase_info, config, y, curvature_radius, band_height, period_count)
    }

    // Draw labels for partials
    if config.strobe_mode == .HARMONIC_MODE &&
       self.display_type == .CURVED_TRACKS &&
       config.partial_labels != .NONE {
        r := min_radius

        for &band, band_idx in phase_info.bands {
            order := len(phase_info.bands) - 1 - band_idx
            cos: f32 = 216
            r += band_height
            sin := math.sqrt(r * r - cos * cos)

            if config.show_band_cents {
                // Cents offset
                rl.DrawTextEx(
                    font_store.medium_32,
                    fmt.ctprintf("%.4f", band.err_cents),
                    {self.position.x + 16, y + band_height * (f32(order) + 0.6) + r - sin},
                    16,
                    0,
                    rl.GetColor(0x82E2FFFF),
                )
            }

            // Partial order, e.g. 1x, 2x, etc
            partial_labels, changed := gui_strobe_partial(
                {self.position.x + 260 + cos, y + band_height * (f32(order) + 0.6) + r - sin},
                config.partial_labels,
                band,
            )
            if changed {
                config.partial_labels = partial_labels
            }
        }
    }

    rl.DrawTexturePro(
        self.shadow_tex,
        rl.Rectangle{0, 0, f32(self.shadow_tex.width), f32(self.shadow_tex.height)},
        rl.Rectangle{0, -20, STROBE_WIDTH, STROBE_HEIGHT + 22},
        rl.Vector2{0, 0},
        0,
        rl.WHITE,
    )

}

// Draw circular bands from the center outwards, so the lowest frequency is the bottom one
@(private)
// The stripe edges are as sharp as the phase is certain: a sharp edge on a jittery phase twitches,
// a soft edge on a clean one looks washed out. The shader draws amp * sin(phase), so an edge spans
// about 2 / amp radians of the strobe phase, keep that a few standard deviations of the phase wide.
STROBE_EDGE_SIGMAS :: 3.0
STROBE_MAX_AMP :: 50.0 // limit, to avoid jagged edges in the strobe display
// The stripes fade in between these SNRs, below it's the background noise (it stays under ~10 dB)
STROBE_FADE_SNR_DB :: [2]f32{8, 16}
STROBE_LOOK_TIME_S :: 0.05

@(private)
update_band_look :: proc(
    self: ^StrobeDisplay,
    band: ^core.PhaseBand,
    band_idx: int,
    period_count: f32,
) -> (
    amp: f32,
    visibility: f32,
) {
    // Uncertainty of the phase as drawn on the screen
    sigma := band.phase_sigma * band.speed * period_count
    target_amp := clamp(2.0 / (STROBE_EDGE_SIGMAS * max(sigma, 1e-6)), 1.0, STROBE_MAX_AMP)

    fade := STROBE_FADE_SNR_DB
    target_visibility := math.smoothstep(fade[0], fade[1], band.snr_db)

    alpha := 1.0 - math.exp(-rl.GetFrameTime() / STROBE_LOOK_TIME_S)
    self.band_amp[band_idx] += alpha * (target_amp - self.band_amp[band_idx])
    self.band_visibility[band_idx] += alpha * (target_visibility - self.band_visibility[band_idx])

    return self.band_amp[band_idx], self.band_visibility[band_idx]
}

draw_strobe_bands :: proc(
    self: ^StrobeDisplay,
    phase_info: ^core.PhaseComparator,
    config: ^Config,
    y: f32,
    curvature_radius: f32,
    band_height: f32,
    period_count: f32,
) {
    curvature_radius := curvature_radius
    period_count := period_count

    for &band, band_idx in phase_info.bands {
        order := len(phase_info.bands) - 1 - band_idx

        rect := rl.Rectangle {
            self.position.x,
            y + band_height * f32(order),
            f32(self.texture_width),
            f32(self.texture_height),
        }

        bounding_rect := [4]f32{rect.x, rect.y, rect.width, rect.height}

        // Note, for concentric circles the radius needs to expand as the bands move from the bottom up
        rl.SetShaderValue(
            self.strobe_shader,
            self.curvature_radius_loc,
            &curvature_radius,
            rl.ShaderUniformDataType.FLOAT,
        )
        curvature_radius += band_height

        rl.SetShaderValue(
            self.strobe_shader,
            self.bounding_rect_loc,
            &bounding_rect,
            rl.ShaderUniformDataType.VEC4,
        )

        rl.SetShaderValue(
            self.strobe_shader,
            self.period_count_loc,
            &period_count,
            rl.ShaderUniformDataType.FLOAT,
        )

        rl.SetShaderValue(
            self.strobe_shader,
            self.time_stretch_loc,
            &band.time_stretch,
            rl.ShaderUniformDataType.FLOAT,
        )

        rl.SetShaderValue(
            self.strobe_shader,
            self.phase_loc,
            &band.scaled_phase,
            rl.ShaderUniformDataType.FLOAT,
        )

        // How far the strobe moved this frame, see determine_band_phase
        phase_step := -band.phase_diff * band.speed
        rl.SetShaderValue(
            self.strobe_shader,
            self.phase_step_loc,
            &phase_step,
            rl.ShaderUniformDataType.FLOAT,
        )

        amp, visibility := update_band_look(self, &band, band_idx, period_count)
        rl.SetShaderValue(self.strobe_shader, self.amp_loc, &amp, rl.ShaderUniformDataType.FLOAT)
        rl.SetShaderValue(
            self.strobe_shader,
            self.visibility_loc,
            &visibility,
            rl.ShaderUniformDataType.FLOAT,
        )

        rl.SetShaderValue(
            self.strobe_shader,
            self.norm_freq_loc,
            &band.norm_freq,
            rl.ShaderUniformDataType.FLOAT,
        )

        rl.SetShaderValue(
            self.strobe_shader,
            self.err_cents_loc,
            &band.err_cents,
            rl.ShaderUniformDataType.FLOAT,
        )

        // Draw
        {
            rl.BeginShaderMode(self.strobe_shader)
            rl.DrawTextureV(self.texture, {rect.x, rect.y + 10}, rl.WHITE)
            rl.EndShaderMode()
        }

        if phase_info.mode == .VERNIER_MODE {
            period_count *= 2.0
        }
    }

}
