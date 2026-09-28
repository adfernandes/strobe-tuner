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

import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:strings"


import "../core"


texture_atlas: Texture

// position can serve as an ID for slider controls
active_slider_position: [2]f32 = {}

// an active dropdown menu or slider dragging should not trigger other GUI controls
exclusive_control_mode := false

text_color_dark := hex(0x15141BFF)
text_color_light := hex(0xBDBDBDFF)


load_texture_atlas :: proc() {
    texture_atlas = gfx_load_texture(#load("../assets/images/atlas.2x.png"))
}

unload_texture_atlas :: proc() {
    gfx_unload_texture(texture_atlas)
}

gui_strobe_mode_toggle :: proc(
    position: [2]f32,
    active_strobe_mode: core.StrobeMode,
) -> (
    core.StrobeMode,
    bool,
) {
    tex_src: Rect
    label: cstring
    label_pos: [2]f32

    if active_strobe_mode == .HARMONIC_MODE {
        tex_src = Rect{0, 96, 240, 48}
        label = "HARMONIC"
        label_pos = [2]f32{position.x + 27.0, position.y + 5}
    } else {
        tex_src = Rect{0, 0, 240, 48}
        label = "VERNIER"
        label_pos = [2]f32{position.x + 32.0, position.y + 5}
    }

    // rounded button texture
    draw_texture(texture_atlas, tex_src, Rect{position.x, position.y, 120, 24})

    draw_text(font_store.medium_28, label, label_pos, 14, 1, text_color_dark)

    if gui_button({position.x, position.y, 120, 24}) {
        if active_strobe_mode == .HARMONIC_MODE do return .VERNIER_MODE, true
        else do return .HARMONIC_MODE, true
    }

    return active_strobe_mode, false
}


gui_feedback_button :: proc(position: [2]f32) {
    // bug icon texture
    draw_texture(texture_atlas, Rect{64, 192, 32, 32}, Rect{position.x, position.y, 16, 16})

    if gui_button({position.x, position.y, 16, 16}) {
        when ODIN_OS == .Darwin {
            libc.system(cstring("open https://github.com/dsego/strobe-tuner"))
        } else when ODIN_OS == .Windows {
            libc.system(cstring("start https://github.com/dsego/strobe-tuner"))
        } else when ODIN_OS == .Linux {
            libc.system(cstring("xdg-open https://github.com/dsego/strobe-tuner"))
        } else {
            fmt.println("Could not open github web page.")
        }
    }
}

gui_strobe_partial :: proc(
    position: [2]f32,
    type: PartialLabelType,
    band: core.PhaseBand,
) -> (
    PartialLabelType,
    bool,
) {

    text: cstring
    text_size: [2]f32
    font := font_store.medium_32
    font_size: f32 = 16

    if type == .FREQUENCY {
        font = font_store.medium_28
        text = fmt.ctprintf("%.1fHz", band.freq_hz)
        font_size = 14
    } else if type == .NOTE_NAMES {
        text = fmt.ctprintf(
            "%v%v%v",
            band.note.name,
            "♯" if band.note.is_accidental else "",
            band.note.octave,
        )
    } else {
        text = fmt.ctprintf("%v×", band.interval)
    }

    text_size = measure_text(font, text, font_size, 0)
    bounds: Rect = {position.x - text_size.x, position.y, text_size.x, text_size.y}

    draw_text(font, text, {bounds.x, bounds.y}, font_size, 0, hex(0x82E2FFFF))

    if gui_button(bounds) {
        if type == .MULTIPLES do return .FREQUENCY, true
        else if type == .FREQUENCY do return .NOTE_NAMES, true
        return .MULTIPLES, true
    }
    return type, false
}


gui_note_detection_mode_toggle :: proc(
    position: [2]f32,
    active_detection_mode: NoteDetectionMode,
) -> (
    NoteDetectionMode,
    bool,
) {
    tex_src: Rect
    label: cstring
    label_pos: [2]f32

    if active_detection_mode == .AUTO {
        tex_src = Rect{0, 48, 240, 48}
        label = "AUTO"
        label_pos = [2]f32{position.x + 42.0, position.y + 5}
    } else {
        tex_src = Rect{0, 0, 240, 48}
        label = "MANUAL"
        label_pos = [2]f32{position.x + 34.0, position.y + 5}
    }

    // rounded button texture
    draw_texture(texture_atlas, tex_src, Rect{position.x, position.y, 120, 24})
    draw_text(font_store.medium_28, label, label_pos, 14, 1, text_color_dark)

    if gui_button({position.x, position.y, 120, 24}) {
        if active_detection_mode == .AUTO do return .MANUAL, true
        else do return .AUTO, true
    }

    return active_detection_mode, false
}


gui_speed_slider :: proc(position: [2]f32, value: ^f32) {
    gui_slider(position, value, 0.001, 0.05)
    // Draw the crosshair icon
    draw_texture(texture_atlas, Rect{32, 192, 32, 32}, Rect{position.x + 6, position.y + 4, 16, 16})
    draw_text(
        font_store.medium_28,
        "SENSITIVITY", // speed ?
        [2]f32{position.x + 32.0, position.y + 5},
        14,
        1,
        text_color_dark,
    )
}


// assumes value is between 0 & 1
gui_slider :: proc(position: [2]f32, value: ^f32, min: f32, max: f32) {
    value^ = clamp(value^, min, max)
    fraction := (value^ - min) / (max - min)

    mouse_point := mouse_position()

    width: f32 = 146
    height: f32 = 24

    bounds := Rect{position.x, position.y, width, height}

    // use position to determine if this is the active slider
    is_active := active_slider_position.x == position.x && active_slider_position.y == position.y

    if exclusive_control_mode && is_active {
        // still dragging
        if mouse_down() {
            fraction = clamp(mouse_point.x - position.x, 0, width) / width
            value^ = math.lerp(min, max, fraction)
        } else {
            exclusive_control_mode = false
            active_slider_position = {}
        }
    } else if point_in_rect(mouse_point, bounds) {
        // start drag
        if !exclusive_control_mode && mouse_down() {
            exclusive_control_mode = true
            active_slider_position = position
            fraction = clamp(mouse_point.x - position.x, 0, width) / width
            value^ = math.lerp(min, max, fraction)
        } else {
            wheel := mouse_wheel()
            if wheel != 0 {
                fraction = clamp(fraction - wheel * 0.05, 0, 1)
                value^ = math.lerp(min, max, fraction)
            }
        }
    }

    slider_position: f32 = fraction * width

    // Draw the slider background
    draw_texture(texture_atlas, Rect{240, 48, width * 2, height * 2}, Rect{position.x, position.y, width, height})
    // Draw the filled (highlighted) area
    draw_texture(texture_atlas, Rect{240, 96, slider_position * 2, height * 2}, Rect{position.x, position.y, slider_position, height})
}

gui_button :: proc(bounds: Rect) -> bool {
    mouse_point := mouse_position()
    if point_in_rect(mouse_point, bounds) && !exclusive_control_mode {
        if mouse_pressed() {
            return true
        }
    }
    return false
}


GuiOption :: struct {
    id:    i32,
    label: string,
}

gui_dropdown :: proc(
    position: [2]f32,
    width: f32,
    options: []GuiOption,
    selected_idx: ^int,
    edit_mode: bool,
    left_pad: f32 = 12,
) -> bool {
    edit_mode := edit_mode
    btn_bounds := Rect{position.x, position.y, width, 24}

    // TODO: make it either a prop or depend on actual width
    max_text_len := 25

    // Draw the button
    {
        // Draw the left part of the dropdown button
        draw_texture(texture_atlas, Rect{0, 144, width * 2, 48}, Rect{position.x, position.y, width - 16, 24})
        // Draw the rounded cap on the right side
        draw_texture(texture_atlas, Rect{0, 144, -32, 48}, Rect{position.x + width - 16, position.y, 16, 24})
        // Draw the triangle icon
        draw_texture(texture_atlas, Rect{128, 192, 32, 32}, Rect{position.x + width - 20, position.y + 4, 16, 16})
    }

    if selected_idx != nil {
        label := strings.cut(options[selected_idx^].label, 0, max_text_len)
        draw_text(
            font_store.medium_28,
            fmt.ctprintf("%s", label),
            {position.x + left_pad, position.y + 5},
            14,
            1,
            text_color_light,
        )
    }

    // menu height without the top & bottom caps
    menu_height := f32(len(options) * 24)
    menu_bounds := Rect{position.x, position.y - menu_height - 30, width, menu_height + 30}

    mouse_point := mouse_position()

    if mouse_pressed() {
        if edit_mode {
            // clicked outside
            if !point_in_rect(mouse_point, menu_bounds) {
                edit_mode = false
                exclusive_control_mode = false
            }
        } else {
            if !exclusive_control_mode && point_in_rect(mouse_point, btn_bounds) {
                edit_mode = true
                exclusive_control_mode = true
            }
        }
    }

    // Draw the dropdown menu
    if edit_mode {
        menu_position := [2]f32{position.x, position.y - menu_height - 30}

        // Top cap
        draw_texture(texture_atlas, Rect{0, 144, width * 2, 24}, Rect{menu_position.x, menu_position.y, width - 16, 12})
        draw_texture(texture_atlas, Rect{0, 144, -32, 24}, Rect{position.x + width - 16, menu_position.y, 16, 12})

        draw_rect(
            {menu_position.x, menu_position.y + 12},
            {width, menu_height},
            hex(0x2D2E35FF),
        )

        // Bottom cap
        draw_texture(texture_atlas, Rect{0, 144, width * 2, -24}, Rect{menu_position.x, menu_position.y + 12 + menu_height, width - 16, 12})
        draw_texture(texture_atlas, Rect{0, 144, -32, -24}, Rect{menu_position.x + width - 16, menu_position.y + 12 + menu_height, 16, 12})
        // debug
        // draw_rect_lines(menu_bounds, 1.0, ORANGE)

        for opt, i in options {
            option_bounds := Rect {
                menu_position.x,
                menu_position.y + 12 + f32(i * 24),
                width,
                24,
            }

            hover := false

            if edit_mode && point_in_rect(mouse_point, option_bounds) {
                hover = true
                if mouse_pressed() {
                    edit_mode = false
                    exclusive_control_mode = false
                    selected_idx^ = i
                }
            }

            if hover {
                draw_rect(
                    {option_bounds.x, option_bounds.y},
                    {option_bounds.width, option_bounds.height},
                    hex(0x15141BFF),
                )
            }

            text_pos := [2]f32{option_bounds.x + 12, option_bounds.y + 4}
            label := strings.cut(opt.label, 0, max_text_len)
            draw_text(
                font_store.medium_28,
                fmt.ctprintf("%s", label),
                text_pos,
                14,
                1,
                hex(0xFFFFFFFF) if hover else text_color_light,
            )
        }
    }

    return edit_mode
}


draw_note :: proc(note: core.Note, pos: [2]f32, freq_estimation_active: bool) {
    if note.frequency == 0 do return

    light_color := hex(0xFBFBFBFF)
    muted_color := hex(0x7D7E8FFF)

    color := light_color if freq_estimation_active else muted_color

    // Note name
    draw_text(font_store.medium_256, fmt.ctprintf("%v", note.name), pos, 128, 0, color)

    // Sharp sign
    if note.is_accidental {
        draw_text(font_store.noto_medium_96, "♯", {pos.x + 76, pos.y + 12}, 48, 0, color)
    }

    // Octave number
    draw_text(
        font_store.medium_76,
        fmt.ctprintf("%v", note.octave),
        {pos.x + 76, pos.y + 72},
        38,
        0,
        color,
    )
}

// pos is the top left of the Hz label
draw_measurements :: proc(
    pos: [2]f32,
    pitch: core.PitchInfo,
    last_good_pitch: core.PitchInfo,
    freq_estimation_active: bool,
    out_of_range: bool,
) {
    show_last := false
    hz := pitch.detected_freq
    cents := pitch.err_cents
    show_placeholder := false

    if !freq_estimation_active || out_of_range {
        if last_good_pitch.measured {
            hz = last_good_pitch.detected_freq
            cents = last_good_pitch.err_cents
        } else {
            show_placeholder = true
        }
    }

    // TODO: define a palette somewhere
    light_color := hex(0xFBFBFBFF)
    muted_color := hex(0x7D7E8FFF)

    color := light_color if freq_estimation_active else muted_color
    font := font_store.bold_36 if freq_estimation_active else font_store.medium_32

    draw_text(font_store.medium_32, "Hz", pos, 16, 1, light_color)

    draw_text(
        font,
        "-" if show_placeholder else fmt.ctprintf("%.1f", hz),
        pos + {0, 21},
        18,
        1,
        color,
    )

    draw_text(font_store.medium_32, "Cents", pos + {85, 0}, 16, 1, light_color)

    cents_str := fmt.ctprintf("%.1f", math.abs(cents))
    show_minus_sign := cents < 0 && cents_str != "0.0"

    if show_minus_sign || show_placeholder {
        draw_text(font, "-", pos + {85, 21}, 18, 1, color)
    }

    draw_text(font, "" if show_placeholder else cents_str, pos + {95, 21}, 18, 1, color)

}
