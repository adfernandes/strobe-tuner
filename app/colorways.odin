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
    CUSTOM,
}


minty: [2]u32 : {0xB5F2DBFF, 0x6B3D7DFF}

vibrant_red: [2]u32 : {0xFF6767FF, 0x6B4949FF}


// Lamp glow on the strobe, cycled with G
GlowPreset :: enum {
    OFF,
    AMBER,
    RED,
}

GlowParams :: struct {
    color:      u32, // filter hue the lamp shines through
    exposure:   f32, // higher shifts the lit stripes towards yellow/white
    saturation: f32, // 1 keeps the full color, lower mixes in gray
}

GLOW_PRESETS := [GlowPreset]GlowParams {
    .OFF   = {},
    .AMBER = {color = 0xFF803CFF, exposure = 4.5, saturation = 0.8},
    .RED   = {color = 0xFF6767FF, exposure = 3.5, saturation = 1.0},
}

get_strobe_colors :: proc(config: ^Config) -> [2]u32 {
    switch config.strobe_colorway {
    case .VIBRANT_RED:
        return vibrant_red
    case .MINTY:
        return minty
    case .CUSTOM:
        return {config.strobe_color_1, config.strobe_color_2}
    }
    return vibrant_red
}
