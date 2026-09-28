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
}

font_store: FontStore

FONT_CODEPOINTS :: "ABCDEFGHIJKLMNOPQRSTUVWYZabcdefghijklmnopqrstuwvxyzz♯♭/+-1234567890.:π!▶︎◀︎×()[]"

init_fonts :: proc() {
    inter_medium := #load("../assets/fonts/inter/Inter-Medium.ttf")
    inter_bold := #load("../assets/fonts/inter/Inter-Bold.ttf")
    noto_sans_mono := #load("../assets/fonts/noto/NotoSansMono-Medium.ttf")

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
}
