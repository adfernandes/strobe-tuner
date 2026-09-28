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

// Where everything goes, worked out every frame from the window size and the safe area, in points.
// A tall window (a phone in portrait) stacks the panel under a taller strobe and moves the controls
// down within thumb reach, anything else gets the desktop layout.

Layout :: struct {
    strobe:         Rect,
    strobe_top:     f32, // top of the visible strobe, below the notch
    strobe_scale:   f32, // size of the strobe tracks relative to the desktop
    note:           [2]f32,
    measurements:   [2]f32, // top right
    stats:          [2]f32,
    lock:           Rect,
    response:       Rect,
    level_meter:    [2]f32,
    settings:       [2]f32,
}

// Taller than wide by this much gets the portrait layout, the desktop window is 488x532
PORTRAIT_ASPECT :: 1.3
PANEL_PADDING :: 16

BUTTON_HEIGHT :: 32
BUTTON_GAP :: 12

// The two buttons share a row, half each
@(private = "file")
button_row :: proc(l: ^Layout, left, right, y: f32) {
    width := (right - left - BUTTON_GAP) / 2
    l.lock = {left, y, width, BUTTON_HEIGHT}
    l.response = {left + width + BUTTON_GAP, y, width, BUTTON_HEIGHT}
}

// Where the right arrow ends, the readout keeps clear of it
@(private = "file")
note_right :: proc(l: Layout) -> f32 {
    return l.note.x + NOTE_WIDTH - NOTE_RIGHT_ARROW_INSET + NOTE_ARROW_SLOT
}

// The readout values sit on the baseline of the note letter
READOUT_VALUE_TOP :: NOTE_BASELINE - 30 // the values are 32pt
READOUT_TOP :: READOUT_VALUE_TOP - 20 // the labels above them
READOUT_WIDTH :: HZ_COLUMN_OFFSET + 95 // enough for "4186.0"
READOUT_HEIGHT :: 60

compute_layout :: proc(window: [2]f32, safe: Rect) -> Layout {
    if window.y > window.x * PORTRAIT_ASPECT do return portrait_layout(window, safe)
    return desktop_layout()
}

@(private = "file")
desktop_layout :: proc() -> (l: Layout) {
    l.strobe = {0, 0, STROBE_WIDTH, STROBE_HEIGHT}
    l.strobe_scale = 1
    l.note = {PANEL_PADDING + NOTE_ARROW_SLOT, 303}
    l.measurements = {STROBE_WIDTH - PANEL_PADDING, l.note.y + READOUT_TOP}
    l.stats = {250, 400}
    button_row(&l, PANEL_PADDING, STROBE_WIDTH - PANEL_PADDING, 438)
    l.level_meter = {16, 507}
    l.settings = {477 - SETTINGS_ICON_SIZE, 520 - SETTINGS_ICON_SIZE}
    return
}

@(private = "file")
portrait_layout :: proc(window: [2]f32, safe: Rect) -> (l: Layout) {
    left := safe.x + PANEL_PADDING
    right := safe.x + safe.width - PANEL_PADDING
    bottom := safe.y + safe.height - PANEL_PADDING

    // The strobe takes about half of the safe area, its background runs up behind the notch
    l.strobe_scale = clamp(0.5 * safe.height / STROBE_HEIGHT, 1, 1.4)
    l.strobe_top = safe.y
    l.strobe = {0, 0, window.x, safe.y + l.strobe_scale * STROBE_HEIGHT}
    panel := l.strobe.y + l.strobe.height

    l.note = {left + NOTE_ARROW_SLOT, panel - 3}
    l.stats = {left + 131, panel + 80}

    // From the bottom up
    l.level_meter = {left, bottom - 10}
    l.settings = {right - SETTINGS_ICON_SIZE, bottom - SETTINGS_ICON_SIZE}
    button_row(&l, left, right, bottom - 36 - BUTTON_HEIGHT)

    // Next to the note when there's room, otherwise in the middle of the space between it and the buttons
    if right - READOUT_WIDTH >= note_right(l) + BUTTON_GAP {
        l.measurements = {right, l.note.y + READOUT_TOP}
    } else {
        note_bottom := l.note.y + NOTE_HEIGHT
        l.measurements = {right, (note_bottom + l.lock.y - READOUT_HEIGHT) / 2}
    }
    return
}

// The settings screen, a column of rows inside the safe area, the same on desktop and phone
SettingsLayout :: struct {
    title: [2]f32,
    close: Rect, // touch area of the ✕
    rows:  [2]f32, // top left of the first row
    width: f32,
}

SETTINGS_ICON_SIZE :: 24 // the cog, bottom right aligned on the main screen
SETTINGS_ROW_HEIGHT :: 52
SETTINGS_CONTROL_HEIGHT :: 32 // the pills, their touch area is the whole row height

compute_settings_layout :: proc(safe: Rect) -> (l: SettingsLayout) {
    left := safe.x + PANEL_PADDING
    top := safe.y + PANEL_PADDING
    l.width = safe.width - 2 * PANEL_PADDING
    l.title = {left, top}
    // Right aligned with the rows, centred on the title
    l.close = {left + l.width - 32, top - 11, 48, 48}
    l.rows = {left, top + 32}
    return
}
