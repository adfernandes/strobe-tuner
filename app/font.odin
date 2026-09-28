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

import "core:math"

FontStore :: struct {
    // regular
    medium_24:      Font,
    medium_28:      Font,
    medium_32:      Font,
    medium_76:      Font,
    medium_256:     Font,

    // Note: Inter doesn't support the sharp sign ♯
    noto_medium_96: Font,

    // bold
    bold_36:        Font,

    // Phosphor icons, see ICON_CODEPOINTS
    icons_32:       Font,
    icons_72:       Font, // the larger icons, sharp at 24pt on a 3x screen
}

font_store: FontStore

FONT_CODEPOINTS :: "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmnopqrstuwvxyzz♯♭#/+-1234567890.:π!▶◀×()[]"

// Phosphor Regular (phosphoricons.com), the font is cut down to these, to add one:
//   uvx --from fonttools pyftsubset Phosphor.ttf --unicodes=U+E272,U+E326,... --no-hinting \
//       --output-file=assets/fonts/phosphor/Phosphor-Icons.ttf
// The codepoints are in the style.css of the @phosphor-icons/web package.
ICON_SLIDERS: cstring : "\ue432"
ICON_GEAR: cstring : ""
ICON_MICROPHONE: cstring : ""
ICON_CARET_DOWN: cstring : ""
ICON_MINUS: cstring : ""
ICON_PLUS: cstring : ""
ICON_X: cstring : ""

ICON_CODEPOINTS :: "\ue432"

init_fonts :: proc() {
    inter_medium := #load("../assets/fonts/inter/Inter-Medium.ttf")
    inter_bold := #load("../assets/fonts/inter/Inter-Bold.ttf")
    noto_sans_mono := #load("../assets/fonts/noto/NotoSansMono-Medium.ttf")
    phosphor := #load("../assets/fonts/phosphor/Phosphor-Icons.ttf")

    font_store.medium_24 = gfx_load_font(inter_medium, 24, FONT_CODEPOINTS)
    font_store.medium_28 = gfx_load_font(inter_medium, 28, FONT_CODEPOINTS)
    font_store.medium_32 = gfx_load_font(inter_medium, 32, FONT_CODEPOINTS)
    font_store.medium_76 = gfx_load_font(inter_medium, 76, FONT_CODEPOINTS)
    font_store.medium_256 = gfx_load_font(inter_medium, 256, FONT_CODEPOINTS)
    font_store.bold_36 = gfx_load_font(inter_bold, 36, FONT_CODEPOINTS)
    font_store.noto_medium_96 = gfx_load_font(noto_sans_mono, 92, FONT_CODEPOINTS)
    font_store.icons_32 = gfx_load_font(phosphor, 32, ICON_CODEPOINTS)
    font_store.icons_72 = gfx_load_font(phosphor, 72, ICON_CODEPOINTS)
}

// The large text is rasterized at exactly the size it's drawn at on this screen, shrinking a larger atlas
// by that much shows jagged edges. Point sizes, whole pixels at 1x, 2x and 3x.
RULER_NOTE_SIZE :: 88 // the target note
RULER_NEIGHBOUR_SIZE :: 52
RULER_OCTAVE_SIZE :: 26
RULER_NOTE_SHARP_SIZE :: 48
RULER_NEIGHBOUR_SHARP_SIZE :: 28
READOUT_SIZE :: 24 // the Hz and cents values, they grow with the ruler
NOTE_ARROW_SIZE :: 26 // either side of the note without the ruler
STROBE_ARROW_SIZE :: 22 // over the strobe, which way to tune

// A font and the point size that draws it one texel to one pixel
PixelFont :: struct {
    font: Font,
    size: f32,
}

PixelFonts :: struct {
    scale:           f32, // the DPI scale they were loaded for
    ruler_scale:     f32, // the ruler's sizes relative to the desktop, see Layout
    note:            PixelFont,
    neighbour:       PixelFont,
    octave:          PixelFont,
    note_sharp:      PixelFont,
    neighbour_sharp: PixelFont,
    readout:         PixelFont,
    note_arrow:      PixelFont,
    strobe_arrow:    PixelFont,
}

pixel_fonts: PixelFonts

// Called before the frame starts, reloads when the window moves to a screen with another scale or the
// layout sizes the ruler differently
update_pixel_fonts :: proc(ruler_scale: f32) {
    scale := gfx_dpi_scale()
    if scale == pixel_fonts.scale && ruler_scale == pixel_fonts.ruler_scale do return
    unload_pixel_fonts()

    inter_medium := #load("../assets/fonts/inter/Inter-Medium.ttf")
    noto_sans_mono := #load("../assets/fonts/noto/NotoSansMono-Medium.ttf")
    load :: proc(ttf: []u8, points, scale: f32, codepoints: string) -> PixelFont {
        pixels := math.round(points * scale)
        return {gfx_load_font(ttf, i32(pixels), codepoints), pixels / scale}
    }

    pixel_fonts = {
        scale           = scale,
        ruler_scale     = ruler_scale,
        note            = load(inter_medium, ruler_scale * RULER_NOTE_SIZE, scale, "ABCDEFG"),
        neighbour       = load(inter_medium, ruler_scale * RULER_NEIGHBOUR_SIZE, scale, "ABCDEFG"),
        octave          = load(inter_medium, ruler_scale * RULER_OCTAVE_SIZE, scale, "0123456789"),
        note_sharp      = load(noto_sans_mono, ruler_scale * RULER_NOTE_SHARP_SIZE, scale, "♯"),
        neighbour_sharp = load(noto_sans_mono, ruler_scale * RULER_NEIGHBOUR_SHARP_SIZE, scale, "♯"),
        readout         = load(inter_medium, ruler_scale * READOUT_SIZE, scale, "0123456789.-"),
        note_arrow      = load(inter_medium, NOTE_ARROW_SIZE, scale, "◀▶"),
        strobe_arrow    = load(inter_medium, STROBE_ARROW_SIZE, scale, "◀▶"),
    }
}

unload_pixel_fonts :: proc() {
    if pixel_fonts.scale == 0 do return
    gfx_unload_font(pixel_fonts.note.font)
    gfx_unload_font(pixel_fonts.neighbour.font)
    gfx_unload_font(pixel_fonts.octave.font)
    gfx_unload_font(pixel_fonts.note_sharp.font)
    gfx_unload_font(pixel_fonts.neighbour_sharp.font)
    gfx_unload_font(pixel_fonts.readout.font)
    gfx_unload_font(pixel_fonts.note_arrow.font)
    gfx_unload_font(pixel_fonts.strobe_arrow.font)
    pixel_fonts = {}
}

// Whole pixels on this screen, so text drawn at a pixel font's size lands texel for pixel
snap_to_pixels :: proc(p: [2]f32) -> [2]f32 {
    scale := pixel_fonts.scale
    return {math.round(p.x * scale), math.round(p.y * scale)} / scale
}

// Icon with its top left at position, 16pt unless told otherwise
draw_icon :: proc(icon: cstring, position: [2]f32, color: Color, size: f32 = 16) {
    font := font_store.icons_72 if size > 16 else font_store.icons_32
    draw_text(font, icon, position, size, 0, color)
}

destroy_fonts :: proc() {
    gfx_unload_font(font_store.medium_24)
    gfx_unload_font(font_store.medium_28)
    gfx_unload_font(font_store.medium_32)
    gfx_unload_font(font_store.medium_76)
    gfx_unload_font(font_store.medium_256)
    gfx_unload_font(font_store.bold_36)
    gfx_unload_font(font_store.noto_medium_96)
    gfx_unload_font(font_store.icons_32)
    gfx_unload_font(font_store.icons_72)
    unload_pixel_fonts()
}
