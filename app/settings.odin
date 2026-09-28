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
import "core:time"

// The settings screen, opened with the cog in the bottom right corner.
// Everything that isn't needed while tuning lives here, the main screen keeps the note lock,
// the strobe mode and the response.

PITCH_STANDARD_MIN :: 400
PITCH_STANDARD_MAX :: 480

SEGMENT_WIDTH :: 60

settings_title_color := hex(0xFBFBFBFF)
settings_separator_color := hex(0x35363EFF)


// Returns close when ✕ is tapped, changed when the strobe or the note detection needs updating
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

    // 16pt icon in the middle of a larger touch area
    draw_icon(ICON_X, {l.close.x + (l.close.width - 16) / 2, l.close.y + (l.close.height - 16) / 2}, icon_color)
    if gui_button(l.close) do close = true

    row := 0

    {
        rect := settings_row(l, row, "Concert A", 176)
        row += 1
        pitch_standard, ok := gui_stepper(
            rect,
            config.pitch_standard,
            1,
            PITCH_STANDARD_MIN,
            PITCH_STANDARD_MAX,
            get_config_defaults().pitch_standard,
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
            left_pad = 36,
            height = rect.height,
        )

        draw_icon(ICON_MICROPHONE, {rect.x + 12, rect.y + (rect.height - 16) / 2}, icon_color)
    }

    {
        // Everything back to the defaults like the R key, including what's only in the config file
        rect := settings_row(l, row, "Reset to defaults", 2 * SEGMENT_WIDTH)
        row += 1
        draw_pill(rect, pill_dark)
        draw_centered_label("Reset", rect, settings_title_color)
        if gui_button(touch_area(rect)) {
            config^ = get_config_defaults()
            changed = true
        }
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


// 24pt icon in the middle of a 2x larger touch area
gui_settings_button :: proc(position: [2]f32) -> bool {
    draw_icon(ICON_GEAR, position, icon_color, SETTINGS_ICON_SIZE)
    return gui_button({position.x - 12, position.y - 12, 48, 48})
}


// Label on the left, the control right aligned, returns where the control goes
@(private = "file")
settings_row :: proc(l: SettingsLayout, index: int, label: cstring, control_width: f32) -> Rect {
    y := l.rows.y + f32(index) * SETTINGS_ROW_HEIGHT

    draw_text(font_store.medium_28, label, {l.rows.x, y + (SETTINGS_ROW_HEIGHT - 14) / 2}, 14, 1, text_color_light)
    draw_rect({l.rows.x, y + SETTINGS_ROW_HEIGHT - 1}, {l.width, 1}, settings_separator_color)

    control_y := y + (SETTINGS_ROW_HEIGHT - SETTINGS_CONTROL_HEIGHT) / 2
    return {l.rows.x + l.width - control_width, control_y, control_width, SETTINGS_CONTROL_HEIGHT}
}

// The pills are slimmer than a finger, taps anywhere in the height of their row count
@(private = "file")
touch_area :: proc(rect: Rect) -> Rect {
    pad := (SETTINGS_ROW_HEIGHT - rect.height) / 2
    return {rect.x, rect.y - pad, rect.width, SETTINGS_ROW_HEIGHT}
}


// One of a few options, the selected one is a yellow pill on a dark track
gui_segmented :: proc(rect: Rect, labels: []cstring, selected: int) -> (int, bool) {
    draw_pill(rect, pill_dark)

    segment_width := rect.width / f32(len(labels))
    for label, i in labels {
        segment := Rect{rect.x + f32(i) * segment_width, rect.y, segment_width, rect.height}

        if i == selected {
            draw_pill(segment, pill_yellow)
            draw_centered_label(label, segment, text_color_dark)
        } else {
            draw_centered_label(label, segment, text_color_light)
            if gui_button(touch_area(segment)) do return i, true
        }
    }

    return selected, false
}


// A value with - and + on either side
gui_stepper :: proc(rect: Rect, value, step, low, high, default: f32, format: string) -> (f32, bool) {
    draw_pill(rect, pill_dark)

    button_width: f32 = 44
    minus := Rect{rect.x, rect.y, button_width, rect.height}
    plus := Rect{rect.x + rect.width - button_width, rect.y, button_width, rect.height}

    icon_offset := [2]f32{(button_width - 16) / 2, (rect.height - 16) / 2}
    draw_icon(ICON_MINUS, {minus.x, minus.y} + icon_offset, icon_color)
    draw_centered_label(fmt.ctprintf(format, value), rect, settings_title_color)
    draw_icon(ICON_PLUS, {plus.x, plus.y} + icon_offset, icon_color)

    if gui_button(touch_area(minus)) do return max(value - step, low), true
    if gui_button(touch_area(plus)) do return min(value + step, high), true

    // Double clicking the value between the buttons puts it back to the default
    if gui_button(touch_area({minus.x + minus.width, rect.y, plus.x - minus.x - minus.width, rect.height})) {
        now := time.tick_now()
        double_click := time.tick_diff(stepper_last_click, now) < 400 * time.Millisecond
        stepper_last_click = now
        if double_click do return default, true
    }

    // Scrolling over the stepper steps too, trackpads scroll in fractions so add them up to whole steps
    if point_in_rect(mouse_position(), touch_area(rect)) && !exclusive_control_mode {
        stepper_scroll += mouse_wheel()
        steps := math.trunc(stepper_scroll)
        stepper_scroll -= steps
        if steps != 0 do return clamp(value + steps * step, low, high), true
    } else {
        stepper_scroll = 0
    }

    return value, false
}

@(private = "file")
stepper_scroll: f32

@(private = "file")
stepper_last_click: time.Tick


@(private = "file")
draw_centered_label :: proc(label: cstring, rect: Rect, color: Color) {
    width := measure_text(font_store.medium_28, label, 14, 1).x
    draw_text(font_store.medium_28, label, {rect.x + (rect.width - width) / 2, rect.y + (rect.height - 14) / 2}, 14, 1, color)
}
