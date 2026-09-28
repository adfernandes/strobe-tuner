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

// The settings screen, opened with the cog in the bottom right corner.
// Everything that isn't needed while tuning lives here, the main screen keeps the note lock,
// the strobe mode and the response.

// Pill rows in the texture atlas (top left, in pixels), each 48px tall
PILL_GRAY :: [2]f32{0, 0}
PILL_DARK :: [2]f32{0, 144}

PITCH_STANDARD_MIN :: 400
PITCH_STANDARD_MAX :: 480

SEGMENT_WIDTH :: 56

settings_title_color := hex(0xFBFBFBFF)
settings_separator_color := hex(0x35363EFF)
settings_icon_color := hex(0x9A9BAAFF)


// Returns close when Done is tapped, changed when the strobe or the note detection needs updating
gui_settings :: proc(
    l: SettingsLayout,
    config: ^Config,
    audio_devices: []GuiOption,
    audio_device_index: ^int,
    audio_device_menu_open: ^bool,
) -> (
    close: bool,
    changed: bool,
) {
    draw_text(font_store.bold_36, "Settings", l.title, 18, 1, settings_title_color)

    draw_pill(PILL_GRAY, l.done)
    draw_centered_label("Done", l.done, text_color_dark)
    if gui_button(l.done) do close = true

    row := 0

    {
        rect := settings_row(l, row, "Concert A", 160)
        row += 1
        pitch_standard, ok := gui_stepper(
            rect,
            config.pitch_standard,
            1,
            PITCH_STANDARD_MIN,
            PITCH_STANDARD_MAX,
            "%.0f Hz",
        )
        if ok {
            config.pitch_standard = pitch_standard
            changed = true
        }
    }

    {
        rect := settings_row(l, row, "Display", 2 * SEGMENT_WIDTH)
        row += 1
        labels := []cstring{"Tracks", "Wheel"}
        if i, ok := gui_segmented(rect, labels, int(config.strobe_display_type)); ok {
            config.strobe_display_type = StrobeDisplayType(i)
        }
    }

    {
        // Custom colors are set in the config file, no segment is selected then
        styles := STROBE_STYLES
        labels: [len(STROBE_STYLES)]cstring
        for style, i in styles do labels[i] = style.label

        rect := settings_row(l, row, "Style", len(styles) * SEGMENT_WIDTH)
        row += 1
        if i, ok := gui_segmented(rect, labels[:], strobe_style_index(config^)); ok {
            // A glow keeps the colorway, turning it off with G brings the stripe colors back
            config.strobe_glow = styles[i].glow
            if styles[i].glow == .OFF do config.strobe_colorway = styles[i].colorway
            changed = true
        }
    }

    {
        // Shown on the curved tracks in harmonic mode
        rect := settings_row(l, row, "Partial labels", 4 * SEGMENT_WIDTH)
        row += 1
        labels := []cstring{"Off", "1×", "Hz", "Note"}
        if i, ok := gui_segmented(rect, labels, int(config.partial_labels)); ok {
            config.partial_labels = PartialLabelType(i)
        }
    }

    {
        rect := settings_row(l, row, "Band cents", 2 * SEGMENT_WIDTH)
        row += 1
        labels := []cstring{"Off", "On"}
        if i, ok := gui_segmented(rect, labels, int(config.show_band_cents)); ok {
            config.show_band_cents = i == 1
        }
    }

    // iOS routes the input itself: built-in mic, headset or an audio interface
    when !IOS {
        // Last, the menu opens upwards over the rows above
        rect := settings_row(l, row, "Input", 240)
        row += 1

        // TODO: add refresh button to show newly connected devices
        audio_device_menu_open^ = gui_dropdown(
            {rect.x, rect.y},
            rect.width,
            audio_devices,
            audio_device_index,
            audio_device_menu_open^,
            left_pad = 32,
        )

        // microphone icon
        mic := [2]f32{rect.x + 8, rect.y + 4}
        draw_texture(texture_atlas, {96, 192, 32, 32}, {mic.x, mic.y, 16, 16})
    }

    return
}


StrobeStyle :: struct {
    label:    cstring,
    colorway: StrobeColorway, // only used without a glow
    glow:     GlowPreset,
}

// The glow lights the stripes with its own lamp color instead of the colorway, so they're picked together
STROBE_STYLES :: [4]StrobeStyle {
    {"Red", .VIBRANT_RED, .OFF},
    {"Minty", .MINTY, .OFF},
    {"Amber", .VIBRANT_RED, .AMBER},
    {"Ruby", .VIBRANT_RED, .RED},
}

// -1 for custom colors
strobe_style_index :: proc(config: Config) -> int {
    styles := STROBE_STYLES
    for style, i in styles {
        if style.glow != config.strobe_glow do continue
        if style.glow != .OFF || style.colorway == config.strobe_colorway do return i
    }
    return -1
}


// Cog glyph, a stand-in until there is an icon in the atlas
gui_settings_button :: proc(position: [2]f32, background: Color) -> bool {
    center := position + {8, 8}

    TEETH :: 8
    for i in 0 ..< TEETH {
        angle := f32(i) / TEETH * math.TAU
        tip := center + 7.5 * [2]f32{math.cos(angle), math.sin(angle)}
        draw_line(center, tip, 3, settings_icon_color)
    }
    draw_circle(center, 5.5, settings_icon_color)
    draw_circle(center, 2.5, background)

    return gui_button({position.x, position.y, 16, 16})
}


// Label on the left, the control right aligned, returns where the control goes
@(private = "file")
settings_row :: proc(l: SettingsLayout, index: int, label: cstring, control_width: f32) -> Rect {
    y := l.rows.y + f32(index) * SETTINGS_ROW_HEIGHT

    draw_text(font_store.medium_28, label, {l.rows.x, y + 15}, 14, 1, text_color_light)
    draw_rect({l.rows.x, y + SETTINGS_ROW_HEIGHT - 1}, {l.width, 1}, settings_separator_color)

    return {l.rows.x + l.width - control_width, y + 10, control_width, 24}
}


// One of a few options, the selected one is a lighter pill on a dark track
gui_segmented :: proc(rect: Rect, labels: []cstring, selected: int) -> (int, bool) {
    draw_pill(PILL_DARK, rect)

    segment_width := rect.width / f32(len(labels))
    for label, i in labels {
        segment := Rect{rect.x + f32(i) * segment_width, rect.y, segment_width, rect.height}

        if i == selected {
            draw_pill(PILL_GRAY, segment)
            draw_centered_label(label, segment, text_color_dark)
        } else {
            draw_centered_label(label, segment, text_color_light)
            if gui_button(segment) do return i, true
        }
    }

    return selected, false
}


// A value with - and + on either side
gui_stepper :: proc(rect: Rect, value, step, low, high: f32, format: string) -> (f32, bool) {
    draw_pill(PILL_DARK, rect)

    button_width := rect.height * 1.5
    minus := Rect{rect.x, rect.y, button_width, rect.height}
    plus := Rect{rect.x + rect.width - button_width, rect.y, button_width, rect.height}

    draw_centered_label("-", minus, text_color_light)
    draw_centered_label(fmt.ctprintf(format, value), rect, settings_title_color)
    draw_centered_label("+", plus, text_color_light)

    if gui_button(minus) do return max(value - step, low), true
    if gui_button(plus) do return min(value + step, high), true

    return value, false
}


// Stretch a pill from the atlas to any width: the left cap, a stretched middle and the left cap flipped
draw_pill :: proc(src: [2]f32, rect: Rect) {
    cap := rect.height * 2 / 3
    middle := rect.width - 2 * cap

    draw_texture(texture_atlas, {src.x, src.y, 32, 48}, {rect.x, rect.y, cap, rect.height})
    if middle > 0 {
        draw_texture(texture_atlas, {src.x + 32, src.y, 16, 48}, {rect.x + cap, rect.y, middle, rect.height})
    }
    draw_texture(texture_atlas, {src.x, src.y, -32, 48}, {rect.x + rect.width - cap, rect.y, cap, rect.height})
}


@(private = "file")
draw_centered_label :: proc(label: cstring, rect: Rect, color: Color) {
    width := measure_text(font_store.medium_28, label, 14, 1).x
    draw_text(font_store.medium_28, label, {rect.x + (rect.width - width) / 2, rect.y + 5}, 14, 1, color)
}
