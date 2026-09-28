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
    measurements:   [2]f32,
    stats:          [2]f32,
    speed_slider:   [2]f32,
    strobe_mode:    [2]f32,
    detection_mode: [2]f32,
    tuning_preset:  [2]f32,
    audio_device:   [2]f32, // desktop only, iOS picks the input itself
    level_meter:    [2]f32,
    feedback:       [2]f32,
}

// Taller than wide by this much gets the portrait layout, the desktop window is 488x532
PORTRAIT_ASPECT :: 1.3
PANEL_PADDING :: 16

compute_layout :: proc(window: [2]f32, safe: Rect) -> Layout {
    if window.y > window.x * PORTRAIT_ASPECT do return portrait_layout(window, safe)
    return desktop_layout()
}

@(private = "file")
desktop_layout :: proc() -> (l: Layout) {
    l.strobe = {0, 0, STROBE_WIDTH, STROBE_HEIGHT}
    l.strobe_scale = 1
    l.note = {16, 303}
    l.measurements = {147, 323}
    l.stats = {250, 400}
    l.speed_slider = {330, 352}
    l.strobe_mode = {16, 456}
    l.detection_mode = {148, 456}
    l.tuning_preset = {278, 456}
    l.audio_device = {12, 496}
    l.level_meter = {264, 507}
    l.feedback = {461, 504}
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

    l.note = {left, panel - 3}
    l.measurements = {left + 131, panel + 17}
    l.stats = {left + 131, panel + 80}

    // From the bottom up
    l.level_meter = {left, bottom - 10}
    l.feedback = {right - 16, bottom - 16}
    l.strobe_mode = {left, bottom - 60}
    l.detection_mode = {left + 132, bottom - 60}
    l.speed_slider = {left, bottom - 104}
    l.tuning_preset = {right - 140, bottom - 104}
    l.audio_device = {left, bottom - 24}
    return
}
