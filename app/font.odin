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
    medium_48:      Font,
    medium_76:      Font,
    medium_192:     Font,
    medium_256:     Font,

    // Note: Inter doesn't support the sharp sign ♯
    noto_medium_96: Font,

    // bold
    bold_32:        Font,
    bold_36:        Font,

    // Phosphor icons, see ICON_CODEPOINTS
    icons_32:       Font,
    icons_72:       Font, // the larger icons, sharp at 24pt on a 3x screen
}

font_store: FontStore

FONT_CODEPOINTS :: "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmnopqrstuwvxyzz♯♭/+-1234567890.:π!▶◀×()[]"

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
    font_store.medium_48 = gfx_load_font(inter_medium, 192, FONT_CODEPOINTS)
    font_store.medium_76 = gfx_load_font(inter_medium, 76, FONT_CODEPOINTS)
    font_store.medium_192 = gfx_load_font(inter_medium, 192, FONT_CODEPOINTS)
    font_store.medium_256 = gfx_load_font(inter_medium, 256, FONT_CODEPOINTS)
    font_store.bold_32 = gfx_load_font(inter_bold, 32, FONT_CODEPOINTS)
    font_store.bold_36 = gfx_load_font(inter_bold, 36, FONT_CODEPOINTS)
    font_store.noto_medium_96 = gfx_load_font(noto_sans_mono, 92, FONT_CODEPOINTS)
    font_store.icons_32 = gfx_load_font(phosphor, 32, ICON_CODEPOINTS)
    font_store.icons_72 = gfx_load_font(phosphor, 72, ICON_CODEPOINTS)
}

// The chromatic ruler's large letters are rasterized at exactly the size they're drawn at on this screen,
// shrinking a larger atlas that much shows jagged edges. Point sizes, whole pixels at 1x, 2x and 3x.
RULER_NOTE_SIZE :: 88 // the target note
RULER_NEIGHBOUR_SIZE :: 52
RULER_OCTAVE_SIZE :: 26
RULER_NOTE_SHARP_SIZE :: 48
RULER_NEIGHBOUR_SHARP_SIZE :: 28

// A font and the point size that draws it one texel to one pixel
PixelFont :: struct {
    font: Font,
    size: f32,
}

RulerFonts :: struct {
    scale:           f32, // the DPI scale they were loaded for
    note:            PixelFont,
    neighbour:       PixelFont,
    octave:          PixelFont,
    note_sharp:      PixelFont,
    neighbour_sharp: PixelFont,
}

ruler_fonts: RulerFonts

// Called before the frame starts, reloads when the window moves to a screen with another scale
update_ruler_fonts :: proc() {
    scale := gfx_dpi_scale()
    if scale == ruler_fonts.scale do return
    unload_ruler_fonts()

    inter_medium := #load("../assets/fonts/inter/Inter-Medium.ttf")
    noto_sans_mono := #load("../assets/fonts/noto/NotoSansMono-Medium.ttf")
    load :: proc(ttf: []u8, points, scale: f32, codepoints: string) -> PixelFont {
        pixels := math.round(points * scale)
        return {gfx_load_font(ttf, i32(pixels), codepoints), pixels / scale}
    }

    ruler_fonts = {
        scale           = scale,
        note            = load(inter_medium, RULER_NOTE_SIZE, scale, "ABCDEFG"),
        neighbour       = load(inter_medium, RULER_NEIGHBOUR_SIZE, scale, "ABCDEFG"),
        octave          = load(inter_medium, RULER_OCTAVE_SIZE, scale, "0123456789"),
        note_sharp      = load(noto_sans_mono, RULER_NOTE_SHARP_SIZE, scale, "♯"),
        neighbour_sharp = load(noto_sans_mono, RULER_NEIGHBOUR_SHARP_SIZE, scale, "♯"),
    }
}

unload_ruler_fonts :: proc() {
    if ruler_fonts.scale == 0 do return
    gfx_unload_font(ruler_fonts.note.font)
    gfx_unload_font(ruler_fonts.neighbour.font)
    gfx_unload_font(ruler_fonts.octave.font)
    gfx_unload_font(ruler_fonts.note_sharp.font)
    gfx_unload_font(ruler_fonts.neighbour_sharp.font)
    ruler_fonts = {}
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
    gfx_unload_font(font_store.medium_48)
    gfx_unload_font(font_store.medium_76)
    gfx_unload_font(font_store.medium_192)
    gfx_unload_font(font_store.medium_256)
    gfx_unload_font(font_store.bold_32)
    gfx_unload_font(font_store.bold_36)
    gfx_unload_font(font_store.noto_medium_96)
    gfx_unload_font(font_store.icons_32)
    gfx_unload_font(font_store.icons_72)
    unload_ruler_fonts()
}
