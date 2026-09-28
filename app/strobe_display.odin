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

import "../core"

shadow_data := #load("../assets/images/shadow.2x.png")

// Bloom for the strobe glow, rendered at a fraction of the strobe size since it gets blurred anyway
BLOOM_DOWNSCALE :: 2
BLOOM_TAP_SPACING :: 1.5 // blur taps spaced apart for a wider glow at the same cost
BLOOM_ITERATIONS :: 2
BLOOM_STRENGTH :: 0.2

StrobeDisplay :: struct {
    strobe_shader:   Shader,
    bloom_shader:    Shader,
    shadow_tex:      Texture,
    colors:          [2]Color,
    background:      Color,
    display_type:    StrobeDisplayType,

    // bloom for the strobe glow, the strobe is rendered into scene_rt and blurred through bloom_rt
    scene_rt:        RenderTarget,
    bloom_rt:        [2]RenderTarget,
    glow_scale:      f32, // DPI scale the render targets were created for
    glow_size:       [2]f32, // and the strobe size in points

    // per band stripe sharpness and visibility, smoothed so they don't flicker, see update_band_look
    band_amp:        [core.MAX_BANDS]f32,
    band_visibility: [core.MAX_BANDS]f32,
}


init_strobe_display :: proc(
    colors: [2]u32,
    background: u32,
    display_type: StrobeDisplayType,
) -> (
    self: StrobeDisplay,
) {
    self.colors = {hex(colors.x), hex(colors.y)}
    self.background = hex(background)
    self.display_type = display_type

    self.strobe_shader = gfx_load_shader(.STROBE)
    self.bloom_shader = gfx_load_shader(.BLOOM)
    self.shadow_tex = gfx_load_texture(shadow_data)

    return
}

setup_strobe_display :: proc(self: ^StrobeDisplay, display_type: StrobeDisplayType) {
    self.display_type = display_type
}

destroy_strobe_display :: proc(self: ^StrobeDisplay) {
    gfx_unload_shader(self.strobe_shader)
    gfx_unload_shader(self.bloom_shader)
    gfx_unload_texture(self.shadow_tex)
    unload_glow_targets(self)
}

@(private)
unload_glow_targets :: proc(self: ^StrobeDisplay) {
    if self.glow_scale == 0 do return
    gfx_unload_render_target(self.scene_rt)
    for rt in self.bloom_rt {
        gfx_unload_render_target(rt)
    }
    self.glow_scale = 0
}

// (Re)create the glow render targets, the scene is rendered at the display's DPI scale to stay sharp
@(private)
ensure_glow_targets :: proc(self: ^StrobeDisplay, size: [2]f32) {
    scale := gfx_dpi_scale()
    if scale == self.glow_scale && size == self.glow_size do return

    unload_glow_targets(self)

    self.scene_rt = gfx_load_render_target(i32(size.x * scale), i32(size.y * scale))
    for &rt in self.bloom_rt {
        rt = gfx_load_render_target(i32(size.x / BLOOM_DOWNSCALE), i32(size.y / BLOOM_DOWNSCALE))
    }
    self.glow_scale = scale
    self.glow_size = size
}

// Separable gaussian blur, ping-pongs between the two targets and ends up in rts[0]
@(private)
blur_render_targets :: proc(
    self: ^StrobeDisplay,
    rts: [2]RenderTarget,
    iterations: int,
    tap_spacing: f32,
) {
    size := render_target_size(rts[0])
    dest := Rect{0, 0, size.x, size.y}

    uniforms := BloomUniforms {
        mode = 1,
    }
    for _ in 0 ..< iterations {
        uniforms.texel_step = {tap_spacing / size.x, 0}
        set_shader_uniforms(self.bloom_shader, &uniforms)
        begin_render_target(rts[1], {})
        draw_render_target(rts[0], dest)
        end_render_target()

        uniforms.texel_step = {0, tap_spacing / size.y}
        set_shader_uniforms(self.bloom_shader, &uniforms)
        begin_render_target(rts[0], {})
        draw_render_target(rts[1], dest)
        end_render_target()
    }
}

// Lift the background a little, as if some lamp light scatters behind the whole disc.
// Based on the darkest stripe, the dark stripes of the outer band away from the hotspot,
// mirrors the light model in the strobe shader.
@(private)
glow_background :: proc(background: Color, glow: GlowParams) -> Color {
    DARK_TRANSMISSION :: 0.3
    MIN_LAMP :: 0.6
    BACKGROUND_LIFT :: 0.25

    glow_color := normalize_color(hex(glow.color)).rgb
    filter := glow_color / max(glow_color.r, glow_color.g, glow_color.b, 0.001)
    filter *= filter

    darkest: [3]f32
    for c, i in filter {
        darkest[i] = 1 - math.exp(-DARK_TRANSMISSION * MIN_LAMP * glow.exposure * c)
    }

    luma := darkest.r * 0.299 + darkest.g * 0.587 + darkest.b * 0.114
    darkest = linalg.lerp([3]f32{luma, luma, luma}, darkest, glow.saturation)

    base := normalize_color(background).rgb
    lifted := linalg.min(base + BACKGROUND_LIFT * darkest, 1)
    return color_from_normalized({lifted.r, lifted.g, lifted.b, 1})
}

@(private)
render_bloom :: proc(self: ^StrobeDisplay) {
    set_blend_mode(.REPLACE)
    defer set_blend_mode(.ALPHA)
    begin_shader(self.bloom_shader)
    defer end_shader()

    // Downsample and keep the bright parts
    scene_size := render_target_size(self.scene_rt)
    uniforms := BloomUniforms {
        mode       = 0,
        texel_step = 1.0 / scene_size,
    }
    set_shader_uniforms(self.bloom_shader, &uniforms)
    bloom_size := render_target_size(self.bloom_rt[0])
    begin_render_target(self.bloom_rt[0], {})
    draw_render_target(self.scene_rt, {0, 0, bloom_size.x, bloom_size.y})
    end_render_target()

    blur_render_targets(self, self.bloom_rt, BLOOM_ITERATIONS, BLOOM_TAP_SPACING)
}

set_display_type :: proc(self: ^StrobeDisplay, display_type: StrobeDisplayType) {
    self.display_type = display_type
}

set_strobe_colors :: proc(self: ^StrobeDisplay, colors: [2]u32) {
    self.colors = {hex(colors.x), hex(colors.y)}
}

// The tracks are laid out for the desktop size and scaled by scale, then aligned to the bottom of rect,
// a taller rect only extends the background upwards (e.g. behind the notch)
draw_strobe_display :: proc(
    self: ^StrobeDisplay,
    rect: Rect,
    scale: f32,
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
    curvature_radius *= scale
    band_height *= scale

    glow_enabled := config.strobe_glow != .OFF
    glow_params := GLOW_PRESETS[config.strobe_glow]

    // Shared by all bands, draw_strobe_bands fills in the rest
    uniforms := StrobeUniforms {
        band_height     = band_height,
        strobe_blur     = i32(config.strobe_blur),
        motion_blur     = i32(config.motion_blur),
        glow            = i32(glow_enabled),
        // The wheel is lit evenly all around, the tracks only show the top of the disc
        lamp_spread     = 1000.0 if self.display_type == .SPINNING_WHEEL else 0.45,
        glow_color      = normalize_color(hex(glow_params.color)),
        glow_exposure   = glow_params.exposure,
        glow_saturation = glow_params.saturation,
        color_a         = normalize_color(self.colors.x),
        color_b         = normalize_color(self.colors.y),
        // most inner radius
        min_radius      = curvature_radius - band_height,
        // most outer radius
        max_radius      = curvature_radius + band_height * f32(len(phase_info.bands) - 1),
    }
    min_radius := uniforms.min_radius

    y := rect.y + rect.height - scale * STROBE_HEIGHT
    if self.display_type == .CURVED_TRACKS {
        y += 32 * scale
    }

    if glow_enabled {
        // Render the strobe offscreen so the bright parts can bloom over the surroundings
        ensure_glow_targets(self, {rect.width, rect.height})

        begin_render_target(
            self.scene_rt,
            glow_background(self.background, glow_params),
            {rect.x, rect.y},
            self.glow_scale,
        )
        draw_strobe_bands(self, rect, phase_info, &uniforms, y, curvature_radius, band_height, period_count)
        end_render_target()

        render_bloom(self)
    }

    begin_scissor(rect)
    defer end_scissor()

    if glow_enabled {
        set_blend_mode(.REPLACE)
        draw_render_target(self.scene_rt, rect)

        // Add the bloom on top, the light spills into the gaps and the dark background
        set_blend_mode(.ADD)
        strength := u8(BLOOM_STRENGTH * 255)
        draw_render_target(self.bloom_rt[0], rect, {strength, strength, strength, 255})
        set_blend_mode(.ALPHA)
    } else {
        draw_rect({rect.x, rect.y}, {rect.width, rect.height}, self.background)
        draw_strobe_bands(self, rect, phase_info, &uniforms, y, curvature_radius, band_height, period_count)
    }

    // Draw labels for partials
    if config.strobe_mode == .HARMONIC_MODE &&
       self.display_type == .CURVED_TRACKS &&
       config.partial_labels != .NONE {
        r := min_radius

        for &band, band_idx in phase_info.bands {
            order := len(phase_info.bands) - 1 - band_idx
            cos := 0.5 * rect.width - 28
            r += band_height
            sin := math.sqrt(r * r - cos * cos)

            if config.show_band_cents {
                // Cents offset
                draw_text(
                    font_store.medium_32,
                    fmt.ctprintf("%.4f", band.err_cents),
                    {rect.x + 16, y + band_height * (f32(order) + 0.6) + r - sin},
                    16,
                    0,
                    hex(0x82E2FFFF),
                )
            }

            // Partial order, e.g. 1x, 2x, etc
            partial_labels, changed := gui_strobe_partial(
                {rect.x + rect.width - 12, y + band_height * (f32(order) + 0.6) + r - sin},
                config.partial_labels,
                band,
            )
            if changed {
                config.partial_labels = partial_labels
            }
        }
    }

    draw_texture(
        self.shadow_tex,
        {0, 0, f32(self.shadow_tex.width), f32(self.shadow_tex.height)},
        {rect.x, rect.y - 20, rect.width, rect.height + 22},
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

    alpha := 1.0 - math.exp(-gfx_frame_time() / STROBE_LOOK_TIME_S)
    self.band_amp[band_idx] += alpha * (target_amp - self.band_amp[band_idx])
    self.band_visibility[band_idx] += alpha * (target_visibility - self.band_visibility[band_idx])

    return self.band_amp[band_idx], self.band_visibility[band_idx]
}

draw_strobe_bands :: proc(
    self: ^StrobeDisplay,
    strobe_rect: Rect,
    phase_info: ^core.PhaseComparator,
    uniforms: ^StrobeUniforms,
    y: f32,
    curvature_radius: f32,
    band_height: f32,
    period_count: f32,
) {
    curvature_radius := curvature_radius
    period_count := period_count

    begin_shader(self.strobe_shader)
    defer end_shader()

    for &band, band_idx in phase_info.bands {
        order := len(phase_info.bands) - 1 - band_idx

        // Down to the bottom of the strobe, the arcs drop towards the sides
        band_y := y + band_height * f32(order)
        rect := Rect{strobe_rect.x, band_y, strobe_rect.width, strobe_rect.y + strobe_rect.height - band_y}

        uniforms.bounding_rect = {rect.x, rect.y, rect.width, rect.height}

        // Note, for concentric circles the radius needs to expand as the bands move from the bottom up
        uniforms.curvature_radius = curvature_radius
        curvature_radius += band_height

        uniforms.period_count = period_count
        uniforms.time_stretch = band.time_stretch
        uniforms.phase = band.scaled_phase

        // How far the strobe moved this frame, see determine_band_phase
        uniforms.phase_step = -band.phase_diff * band.speed

        uniforms.amp, uniforms.visibility = update_band_look(self, &band, band_idx, period_count)
        uniforms.norm_freq = band.norm_freq
        uniforms.err_cents = band.err_cents

        set_shader_uniforms(self.strobe_shader, uniforms)
        draw_shader_quad({rect.x, rect.y + 10, rect.width, rect.height})

        if phase_info.mode == .VERNIER_MODE {
            period_count *= 2.0
        }
    }
}
