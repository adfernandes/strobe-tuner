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

StrobeColorway :: enum {
    VIBRANT_RED,
    MINTY,
    AMBER,
    MONO,
}


minty: [2]u32 : {0xB5F2DBFF, 0x6B3D7DFF}

vibrant_red: [2]u32 : {0xFF6767FF, 0x6B4949FF}

amber: [2]u32 : {0xFF9A4DFF, 0x6B4A38FF}

// Black and white, the most contrast and no hue to tell apart
mono: [2]u32 : {0xF2F1ECFF, 0x55565EFF}


// Lamp glow on the strobe, the lamp-lit look of the old mechanical strobe tuners, toggled with G.
// The lamp shines through a filter in the colorway's hue.
GlowParams :: struct {
    color:      u32, // filter hue the lamp shines through
    dark_color: u32, // filter hue of the dark stripes, the same as color for a single hue
    exposure:   f32, // higher shifts the lit stripes towards yellow/white
    saturation: f32, // 1 keeps the full color, lower mixes in gray
}

get_glow_params :: proc(config: ^Config) -> GlowParams {
    switch config.strobe_colorway {
    case .VIBRANT_RED:
        return {color = 0xFF6767FF, dark_color = 0xFF6767FF, exposure = 3.5, saturation = 0.75}
    case .MINTY:
        return {color = 0x7DF2C4FF, dark_color = minty[1], exposure = 3.0, saturation = 1.0}
    case .AMBER:
        return {color = 0xFF803CFF, dark_color = 0xFF803CFF, exposure = 4.5, saturation = 0.8}
    case .MONO:
        // The warm white of a bulb
        return {color = 0xFFE2B8FF, dark_color = 0xFFE2B8FF, exposure = 3.5, saturation = 0.8}
    }
    return {}
}

get_strobe_colors :: proc(config: ^Config) -> [2]u32 {
    switch config.strobe_colorway {
    case .VIBRANT_RED:
        return vibrant_red
    case .MINTY:
        return minty
    case .AMBER:
        return amber
    case .MONO:
        return mono
    }
    return vibrant_red
}
