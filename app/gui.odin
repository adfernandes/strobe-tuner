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
text_color_white := hex(0xFBFBFBFF) // the note and readout while there's a pitch, titles
text_color_muted := hex(0x7D7E8FFF) // the note and readout without a pitch, the ruler's neighbours
icon_color := hex(0x9A9BAAFF)

// Buttons
pill_gray := text_color_muted
pill_mint := hex(0x61FFCAFF)
pill_violet := hex(0xA277FFFF)
pill_yellow := hex(0xFFCA85FF)
pill_dark := hex(0x2D2E35FF)

// A label with an LED to its left that lights up while the toggle is on, like the indicator lamps on
// old hardware. pos is the left edge, vertically centred.
gui_led_toggle :: proc(pos: [2]f32, label: cstring, on: bool, color: Color) -> bool {
    LED_SIZE :: 8
    LABEL_GAP :: 10
    TOUCH_HEIGHT :: 44

    led := Rect{pos.x, pos.y - LED_SIZE / 2, LED_SIZE, LED_SIZE}
    if on {
        // A thin ring of light, stepped down over a few points
        for ring in ([2][2]f32{{3, 50}, {1.5, 110}}) {
            glow := color
            glow.a = u8(ring[1])
            draw_pill({led.x - ring[0], led.y - ring[0], led.width + 2 * ring[0], led.height + 2 * ring[0]}, glow)
        }
    }
    draw_pill(led, color if on else pill_dark)

    label_x := pos.x + LED_SIZE + LABEL_GAP
    label_width := measure_text(font_store.medium_28, label, 14, 1).x
    draw_text(font_store.medium_28, label, {label_x, pos.y - 7}, 14, 1, text_color_white if on else text_color_light)

    // The whole of the LED and the label, a little past them on each side
    width := label_x + label_width - pos.x
    return gui_button({pos.x - 12, pos.y - TOUCH_HEIGHT / 2, width + 24, TOUCH_HEIGHT})
}

LOCK_BUTTON_HEIGHT :: 24

// The most important toggle gets a whole button, gray while off and violet while locked. center is the
// middle of the button.
gui_lock_toggle :: proc(center: [2]f32, locked: bool) -> bool {
    LABEL :: "LOCK NOTE"
    LABEL_SIZE :: 14
    PADDING :: 10
    TOUCH_HEIGHT :: 44

    label_size := measure_text(font_store.medium_28, LABEL, LABEL_SIZE, 1)
    width := label_size.x + 2 * PADDING
    rect := Rect{center.x - width / 2, center.y - LOCK_BUTTON_HEIGHT / 2, width, LOCK_BUTTON_HEIGHT}

    draw_pill(rect, pill_violet if locked else pill_gray)
    draw_text(font_store.medium_28, LABEL, snap_to_pixels(center - label_size / 2), LABEL_SIZE, 1, text_color_dark)

    return gui_button({rect.x, center.y - TOUCH_HEIGHT / 2, rect.width, TOUCH_HEIGHT})
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


// Without the ruler: the note on its own with arrows either side to step it, the layout leaves room for them
NOTE_ARROW_SLOT :: 32
NOTE_WIDTH :: 112
NOTE_HEIGHT :: 116
NOTE_BASELINE :: 98 // bottom of the letter, from the top of the note
// The octave number ends short of NOTE_WIDTH, the right arrow moves in to be as far from it as the left one
NOTE_RIGHT_ARROW_INSET :: 13

draw_note :: proc(note: core.Note, pos: [2]f32, freq_estimation_active: bool) {
    if note.frequency == 0 do return

    color := text_color_white if freq_estimation_active else text_color_muted

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

// A locked note shows arrows either side of it to step by a semitone
gui_note_arrows :: proc(pos: [2]f32, locked: bool) -> (step: int) {
    if !locked do return

    prev := Rect{pos.x - NOTE_ARROW_SLOT, pos.y, NOTE_ARROW_SLOT, NOTE_HEIGHT}
    next := Rect{pos.x + NOTE_WIDTH - NOTE_RIGHT_ARROW_INSET, pos.y, NOTE_ARROW_SLOT, NOTE_HEIGHT}

    font := pixel_fonts.note_arrow
    ARROW_HEIGHT :: 18 // of the triangle itself, it sits in the middle of the line
    for arrow, i in ([2]cstring{"◀", "▶"}) {
        slot := prev if i == 0 else next
        size := measure_text(font.font, arrow, font.size, 0)
        // Sitting on the baseline of the letter
        center_y := slot.y + NOTE_BASELINE - ARROW_HEIGHT / 2
        position := snap_to_pixels({slot.x + (slot.width - size.x) / 2, center_y - size.y / 2})
        draw_text(font.font, arrow, position, font.size, 0, text_color_white)
    }

    // A finger is wider than the slots, the touch areas reach a little past them
    if gui_button({prev.x - 6, prev.y, prev.width + 12, prev.height}) do step = -1
    if gui_button({next.x - 6, next.y, next.width + 12, next.height}) do step = 1

    return
}


// The chromatic ruler, all the notes in a row with the target note large in the middle.
// The notes slide over to the next semitone, further jumps snap. The sizes don't change, the target is large wherever it is.
// The fonts are loaded at the exact sizes, see update_pixel_fonts, and everything lands on whole pixels.

RULER_MIN_SPACING :: 70 // between the letters of neighbouring semitones, room for a sharp between them
RULER_CENTER_GAP :: 30 // extra room either side of the large note
RULER_EDGE :: 36 // half a letter and a sharp, the outermost ones end at the edges
RULER_MAX_PER_SIDE :: 2
RULER_SLIDE_SPEED :: 14 // per second, how quickly the slide closes the distance
RULER_LOWEST :: -48 // A0, in semitones from A4
RULER_HIGHEST :: 39 // C8

// Where the middle of the ruler is, in semitones from A4, it follows the target note a little behind
ruler_position: f32
ruler_initialized: bool

// Returns how many semitones to step when another note is tapped
gui_note_ruler :: proc(rect: Rect, note: core.Note, active: bool) -> (step: int) {
    if note.frequency == 0 do return

    target := note.cents / 100

    // Slide to the next semitone, anything further snaps, and settle exactly on the note
    if !ruler_initialized || abs(f32(target) - ruler_position) > 1 {
        ruler_position = f32(target)
        ruler_initialized = true
    }
    ruler_position += (f32(target) - ruler_position) * min(1, RULER_SLIDE_SPEED * gfx_frame_time())
    if abs(f32(target) - ruler_position) < 0.002 do ruler_position = f32(target)

    center := [2]f32{rect.x + rect.width / 2, rect.y + rect.height / 2}

    // The gaps grow with the letters, the fonts were loaded at the layout's size
    s := pixel_fonts.ruler_scale
    center_gap := s * RULER_CENTER_GAP

    // As many neighbours as fit, up to 2 a side, spread out to reach the edges
    room := rect.width / 2 - s * RULER_EDGE - center_gap
    per_side := clamp(int(room / (s * RULER_MIN_SPACING)), 1, RULER_MAX_PER_SIDE)
    spacing := room / f32(per_side)

    // The target note is white while there's a pitch, like the note without the ruler
    note_color := text_color_white if active else text_color_muted

    // Notes slide in and out at the edges
    begin_scissor(rect)
    defer end_scissor()

    first := max(int(math.floor(ruler_position)) - per_side - 1, RULER_LOWEST)
    last := min(int(math.ceil(ruler_position)) + per_side + 1, RULER_HIGHEST)
    for k in first ..= last {
        offset := f32(k) - ruler_position
        distance := abs(offset)
        x := center.x + offset * spacing + math.sign(offset) * center_gap * min(distance, 1)

        if k == target {
            draw_ruler_note(note, {x, center.y}, pixel_fonts.note, pixel_fonts.note_sharp, true, note_color)
            continue
        }

        n := core.cents_to_note(f32(k * 100), note.pitch_standard)
        draw_ruler_note(n, {x, center.y}, pixel_fonts.neighbour, pixel_fonts.neighbour_sharp, false, text_color_muted)

        // Tapping another note locks it
        if distance <= f32(per_side) {
            if gui_button({x - spacing / 2, rect.y, spacing, rect.height}) do step = k - target
        }
    }

    return
}

// The name centred on pos, the sharp and the octave (only on the target) to the right.
// Drawn at the fonts' own size, one texel to one pixel.
@(private = "file")
draw_ruler_note :: proc(n: core.Note, pos: [2]f32, name_font, sharp_font: PixelFont, show_octave: bool, color: Color) {
    size := name_font.size

    name := fmt.ctprintf("%v", n.name)
    name_size := measure_text(name_font.font, name, size, 0)

    // Centred on the letter, the sharp hangs off to the right so the letters are evenly spaced
    top_left := snap_to_pixels(pos - name_size / 2)
    draw_text(name_font.font, name, top_left, size, 0, color)

    right := top_left.x + name_size.x
    if n.is_accidental {
        sharp_pos := snap_to_pixels({right, top_left.y + 0.1 * size})
        draw_text(sharp_font.font, "♯", sharp_pos, sharp_font.size, 0, color)
    }

    if show_octave {
        octave := pixel_fonts.octave
        octave_pos := snap_to_pixels({right, top_left.y + name_size.y - 1.3 * octave.size})
        draw_text(octave.font, fmt.ctprintf("%v", n.octave), octave_pos, octave.size, 0, color)
    }
}


// Strobe speeds per cent of detuning, fast spins 4× faster for the final adjustment
RESPONSE_SPEEDS :: [2]f32{0.0125, 0.05}

// Slow unless the LED is lit
gui_response_toggle :: proc(pos: [2]f32, speed: f32) -> (f32, bool) {
    speeds := RESPONSE_SPEEDS

    // The config can hold any speed, show the closest step
    step := 0
    for s, i in speeds {
        if abs(math.log2(s / speed)) < abs(math.log2(speeds[step] / speed)) do step = i
    }

    if gui_led_toggle(pos, "FAST", step == 1, pill_mint) {
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


ReadoutAlign :: enum {
    RIGHT, // the right edges of both columns are fixed, pos is the top right of the cents column
    CENTER, // pos is the top middle of the gutter, Hz right aligned before it and cents left aligned after it
}

// Two columns, Hz and cents. Centred, the minus hangs into the gutter so the pair looks centred whatever
// the digits.
draw_measurements :: proc(
    pos: [2]f32,
    align: ReadoutAlign,
    pitch: core.PitchInfo,
    last_good_pitch: core.PitchInfo,
    freq_estimation_active: bool,
    out_of_range: bool,
) {
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

    color := text_color_white if freq_estimation_active else text_color_muted
    value := pixel_fonts.readout

    // The labels stay in the background, the values and the note are what's read
    LABEL_SIZE :: 14
    VALUE_Y :: 18
    label_font := font_store.medium_32
    hz_str := "-" if show_placeholder else fmt.ctprintf("%.1f", hz)
    cents_str := "-" if show_placeholder else fmt.ctprintf("%.1f", math.abs(cents))
    minus := !show_placeholder && cents < 0 && cents_str != "0.0"

    switch align {
    case .CENTER:
        hz_right := pos + {-READOUT_GUTTER / 2, 0}
        draw_text_right(label_font, "Hz", hz_right, LABEL_SIZE, 1, text_color_muted)
        draw_text_right(value.font, hz_str, hz_right + {0, VALUE_Y}, value.size, 0, color)

        cents_left := pos + {READOUT_GUTTER / 2, 0}
        draw_text(label_font, "Cents", snap_to_pixels(cents_left), LABEL_SIZE, 1, text_color_muted)
        draw_text(value.font, cents_str, snap_to_pixels(cents_left + {0, VALUE_Y}), value.size, 0, color)
        if minus do draw_text_right(value.font, "-", cents_left + {-2, VALUE_Y}, value.size, 0, color)
    case .RIGHT:
        hz_right := pos + {-HZ_COLUMN_OFFSET, 0}
        draw_text_right(label_font, "Hz", hz_right, LABEL_SIZE, 1, text_color_muted)
        draw_text_right(value.font, hz_str, hz_right + {0, VALUE_Y}, value.size, 0, color)

        draw_text_right(label_font, "Cents", pos, LABEL_SIZE, 1, text_color_muted)
        width := draw_text_right(value.font, cents_str, pos + {0, VALUE_Y}, value.size, 0, color)
        // The minus hangs to the left of the number
        if minus do draw_text_right(value.font, "-", pos + {-width - 2, VALUE_Y}, value.size, 0, color)
    }
}

// Between the columns of the centred readout, room for the minus
READOUT_GUTTER :: 40

// From the right edge of the cents column to the right edge of the Hz column
HZ_COLUMN_OFFSET :: 100

// pos is the top right of the text, returns its width
draw_text_right :: proc(font: Font, text: cstring, pos: [2]f32, size, spacing: f32, color: Color) -> f32 {
    width := measure_text(font, text, size, spacing).x
    draw_text(font, text, snap_to_pixels({pos.x - width, pos.y}), size, spacing, color)
    return width
}
