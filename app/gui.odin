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
import "core:strings"


import "../core"


// an active dropdown menu should not trigger other GUI controls
exclusive_control_mode := false

text_color_dark := hex(0x15141BFF)
text_color_light := hex(0xBDBDBDFF)
icon_color := hex(0x9A9BAAFF)

// Buttons
pill_gray := hex(0x7D7E8FFF)
pill_mint := hex(0x61FFCAFF)
pill_violet := hex(0xA277FFFF)
pill_yellow := hex(0xFFCA85FF)
pill_dark := hex(0x2D2E35FF)

// Gray while the note follows the detected pitch, violet while it's locked
gui_lock_toggle :: proc(rect: Rect, locked: bool) -> bool {
    draw_pill(rect, pill_violet if locked else pill_gray)
    draw_centered_label("LOCK NOTE", rect, text_color_dark)
    return gui_button(rect)
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


// Width of the slots either side of the note that hold the arrows, the layout leaves room for them
NOTE_ARROW_SLOT :: 32
NOTE_WIDTH :: 112
NOTE_HEIGHT :: 116
NOTE_BASELINE :: 98 // bottom of the letter, from the top of the note
// The octave number ends short of NOTE_WIDTH, the right arrow moves in to be as far from it as the left one
NOTE_RIGHT_ARROW_INSET :: 13

// A locked note shows arrows either side of it to step by a semitone
gui_note_arrows :: proc(pos: [2]f32, locked: bool) -> (step: int) {
    if !locked do return

    prev := Rect{pos.x - NOTE_ARROW_SLOT, pos.y, NOTE_ARROW_SLOT, NOTE_HEIGHT}
    next := Rect{pos.x + NOTE_WIDTH - NOTE_RIGHT_ARROW_INSET, pos.y, NOTE_ARROW_SLOT, NOTE_HEIGHT}

    // Drawn from the large font so they stay sharp on 3x screens
    ARROW_SIZE :: 26
    ARROW_HEIGHT :: 18 // of the triangle itself, it sits in the middle of the line
    for arrow, i in ([2]cstring{"◀", "▶"}) {
        slot := prev if i == 0 else next
        size := measure_text(font_store.medium_192, arrow, ARROW_SIZE, 0)
        // Sitting on the baseline of the letter
        center_y := slot.y + NOTE_BASELINE - ARROW_HEIGHT / 2
        position := [2]f32{slot.x + (slot.width - size.x) / 2, center_y - size.y / 2}
        draw_text(font_store.medium_192, arrow, position, ARROW_SIZE, 0, hex(0xFBFBFBFF))
    }

    // A finger is wider than the slots, the touch areas reach a little past them
    if gui_button({prev.x - 6, prev.y, prev.width + 12, prev.height}) do step = -1
    if gui_button({next.x - 6, next.y, next.width + 12, next.height}) do step = 1

    return
}


// Strobe speeds per cent of detuning, fast spins 4× faster for the final adjustment
RESPONSE_SPEEDS :: [2]f32{0.0125, 0.05}
RESPONSE_LABELS :: [2]cstring{"SLOW", "FAST"}

gui_response_toggle :: proc(rect: Rect, speed: f32) -> (f32, bool) {
    speeds := RESPONSE_SPEEDS
    labels := RESPONSE_LABELS

    // The config can hold any speed, show the closest step
    step := 0
    for s, i in speeds {
        if abs(math.log2(s / speed)) < abs(math.log2(speeds[step] / speed)) do step = i
    }

    draw_pill(rect, pill_yellow if step == 0 else pill_mint)
    draw_centered_label(labels[step], rect, text_color_dark)

    if gui_button(rect) {
        return speeds[(step + 1) % len(speeds)], true
    }

    return speed, false
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

// Whether the button is being held down, to draw it in its pressed shade
gui_button_held :: proc(bounds: Rect) -> bool {
    return mouse_down() && point_in_rect(mouse_position(), bounds) && !exclusive_control_mode
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
    height: f32 = 24,
) -> bool {
    edit_mode := edit_mode
    btn_bounds := Rect{position.x, position.y, width, height}

    // TODO: make it either a prop or depend on actual width
    max_text_len := 25

    // Draw the button
    draw_pill(btn_bounds, pill_dark)
    draw_icon(ICON_CARET_DOWN, {position.x + width - 22, position.y + (height - 16) / 2}, icon_color)

    if selected_idx != nil {
        label := strings.cut(options[selected_idx^].label, 0, max_text_len)
        draw_text(
            font_store.medium_28,
            fmt.ctprintf("%s", label),
            {position.x + left_pad, position.y + (height - 14) / 2},
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

        // Options with a 12pt rounded margin above and below
        draw_rounded_rect({menu_position.x, menu_position.y, width, menu_height + 24}, 12, pill_dark)
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

// Two right aligned columns, Hz and cents, pos is the top right of the cents column
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
    // Drawn from the large font so the values stay sharp on 3x screens
    font := font_store.medium_48

    // The right edge of each column is fixed so the digits don't shift sideways
    LABEL_SIZE :: 16
    VALUE_SIZE :: 32
    VALUE_Y :: 20
    hz_right := pos + {-HZ_COLUMN_OFFSET, 0}

    draw_text_right(font_store.medium_32, "Hz", hz_right, LABEL_SIZE, 1, light_color)
    hz_str := "-" if show_placeholder else fmt.ctprintf("%.1f", hz)
    draw_text_right(font, hz_str, hz_right + {0, VALUE_Y}, VALUE_SIZE, 0, color)

    draw_text_right(font_store.medium_32, "Cents", pos, LABEL_SIZE, 1, light_color)

    cents_str := fmt.ctprintf("%.1f", math.abs(cents))
    show_minus_sign := cents < 0 && cents_str != "0.0"

    if show_placeholder {
        draw_text_right(font, "-", pos + {0, VALUE_Y}, VALUE_SIZE, 0, color)
    } else {
        draw_text_right(font, cents_str, pos + {0, VALUE_Y}, VALUE_SIZE, 0, color)
        // The minus hangs to the left of the number
        if show_minus_sign {
            width := measure_text(font, cents_str, VALUE_SIZE, 0).x
            draw_text_right(font, "-", pos + {-width - 2, VALUE_Y}, VALUE_SIZE, 0, color)
        }
    }
}

// From the right edge of the cents column to the right edge of the Hz column
HZ_COLUMN_OFFSET :: 120

// pos is the top right of the text
draw_text_right :: proc(font: Font, text: cstring, pos: [2]f32, size, spacing: f32, color: Color) {
    width := measure_text(font, text, size, spacing).x
    draw_text(font, text, {pos.x - width, pos.y}, size, spacing, color)
}
