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


import "base:intrinsics"
import "base:runtime"
import "core:encoding/ini"
import "core:fmt"
import "core:reflect"
import "core:strconv"
import "core:strings"


import "../core"

MAX_INTERVALS :: 8


PartialLabelType :: enum {
    NONE,
    MULTIPLES,
    FREQUENCY,
    NOTE_NAMES,
}

StrobeDisplayType :: enum {
    CURVED_TRACKS,
    SPINNING_WHEEL,
}


Config :: struct {
    // Initial target frequency for the strobe
    target_freq_hz:               f32,

    // eg A 440Hz
    pitch_standard:               f32,

    // how many spinning bands to show
    strobe_intervals:             [MAX_INTERVALS]f32,
    strobe_intervals_index:       int,

    // FFT length for the pitch detector, e.g. 4096 samples
    pitch_detect_fft_size:        int,

    // audio card sampling rate, e.g. 44.100 Hz
    samplerate:                   int,

    // harmonic to track multiple frequencies or "fine" to track one pitch at different sensitivities
    strobe_mode:                  core.StrobeMode,

    // the sensitivity or speed of the base strobe band,
    // i.e. how fast should the spinning effect be in response to the phase difference
    strobe_speed:                 f32,

    // if multiple strobe bands, this sensitivity multiplier will be applied to subsequent spinning bands
    speed_multiplier:             f32,

    // How to render the strobe effect
    strobe_display_type:          StrobeDisplayType,

    // color scheme for strobe track display, two hex values
    strobe_color_1:               u32 "color",
    strobe_color_2:               u32 "color",
    strobe_colorway:              StrobeColorway,
    strobe_blur:                  bool,
    // average the strobe pattern over its movement since the previous frame, reduces shimmer when it spins fast
    motion_blur:                  bool,
    // lamp-lit look of the old mechanical strobe tuners, see GLOW_PRESETS
    strobe_glow:                  GlowPreset,
    prevent_strobe_octave_jumps:  bool,

    // show different type of partial labels, eg partial number 1x, note name A2, or frequency 110Hz
    partial_labels:               PartialLabelType,

    // pitch detection settings
    pitch_detection_clarity_low:  f32,
    pitch_detection_clarity_high: f32,
    noise_floor_snr_db_threshold: f32,
    pitch_detection_min_snr_db:   f32,
    rms_quiet_threshold:          f32,

    // number of consecutive pitch detections of a new note before the strobe switches to it
    note_switch_confirmations:    int,

    // high-pass filter on the input to remove DC and low frequency rumble, 0 to disable
    highpass_cutoff_hz:           f32,

    // Average 3 DFTs to get more stable phase/mag tracking
    use_phase_average:            bool,

    // Show cents offset for each strobe band
    show_band_cents:              bool,
}

@(private)
config_defaults :: Config {
    target_freq_hz               = 110.0,
    pitch_standard               = 440.0,
    strobe_intervals             = {1, 2, 4, 0, 0, 0, 0, 0},
    strobe_intervals_index       = 0,
    pitch_detect_fft_size        = 8192,
    samplerate                   = 48_000,
    strobe_mode                  = .HARMONIC_MODE,
    strobe_speed                 = 0.0125,
    speed_multiplier             = 2.0,
    strobe_display_type          = .CURVED_TRACKS,
    strobe_colorway              = .VIBRANT_RED,
    strobe_blur                  = true,
    motion_blur                  = true,
    strobe_glow                  = .AMBER,
    prevent_strobe_octave_jumps  = true,

    // Custom colors
    strobe_color_1               = 0x0,
    strobe_color_2               = 0x0,

    //
    partial_labels               = .MULTIPLES,
    pitch_detection_clarity_low  = 0.9,
    pitch_detection_clarity_high = 0.98,
    noise_floor_snr_db_threshold = 10, // to determine if it’s safe to update the noise floor
    pitch_detection_min_snr_db   = 2, // dB
    rms_quiet_threshold          = 0.01, // -40dBFS
    note_switch_confirmations    = 3, // ~150ms at 20 detections per second, the last one must be strong
    highpass_cutoff_hz           = 60, // below guitar low E (82Hz), lower it for bass
    use_phase_average            = true,
    show_band_cents              = false,
}


get_config_defaults :: proc() -> Config {
    return config_defaults
}

// Load config from the standard OS path, eg ~/Library/Application Support/StrobeTuner/config.ini on MacOS.
load_config :: proc() -> Config {

    config := get_config_defaults()

    ini_map, ok := load_ini()
    defer if ok do ini.delete_map(ini_map)
    section := ini_map[""]

    fields := reflect.struct_fields_zipped(Config)

    for field in fields {
        value := reflect.struct_field_value(config, field)
        ptr := rawptr(uintptr(&config) + field.offset)

        #partial switch v in field.type.variant {
        case reflect.Type_Info_Named:
            named := field.type.variant.(reflect.Type_Info_Named)
            value, ok := reflect.enum_from_name_any(field.type.id, section[field.name])
            if ok {
                write_int_field(ptr, field.type.size, int(value))
            }
        case reflect.Type_Info_Float:
            value, ok := strconv.parse_f32(section[field.name])
            if ok {
                ptr_f32 := cast(^f32)ptr
                ptr_f32^ = value
            }
        case reflect.Type_Info_Integer:
            str := section[field.name]
            value: int
            ok: bool
            // Colors are hex, older configs were saved with an uppercase 0X prefix that parse_int rejects
            if field.tag == "color" && (strings.has_prefix(str, "0x") || strings.has_prefix(str, "0X")) {
                value, ok = strconv.parse_int(str[2:], 16)
            } else {
                value, ok = strconv.parse_int(str)
            }
            if ok {
                write_int_field(ptr, field.type.size, value)
            }
        case reflect.Type_Info_Boolean:
            value, ok := strconv.parse_bool(section[field.name])
            if ok {
                ptr_bool := cast(^bool)ptr
                ptr_bool^ = value
            }
        case reflect.Type_Info_Array:
            trimmed := strings.trim(section[field.name], "[] ")
            if len(trimmed) > 0 {
                split := strings.split(trimmed, ",")
                defer delete(split)
                ptr_array := cast(^[MAX_INTERVALS]f32)ptr
                l := len(split)
                for i in 0 ..< l {
                    trimmed := strings.trim(split[i], " ")
                    value, ok := strconv.parse_f32(trimmed)
                    if ok {
                        ptr_array^[i] = value
                    }
                }
                // Fill in the rest
                for i in l ..< MAX_INTERVALS do ptr_array^[i] = 0.0
            }
        }
    }

    return config
}


// Write with the field's own size, writing a full int into a smaller field clobbers the next one
@(private)
write_int_field :: proc(ptr: rawptr, size: int, value: int) {
    switch size {
    case 1:
        (^u8)(ptr)^ = u8(value)
    case 2:
        (^u16)(ptr)^ = u16(value)
    case 4:
        (^u32)(ptr)^ = u32(value)
    case 8:
        (^int)(ptr)^ = value
    case:
        fmt.println("Unsupported config field size", size)
    }
}

save_config :: proc(config: Config) {
    ini_map := ini.Map{}
    defer ini.delete_map(ini_map)

    section: map[string]string = {}
    fields := reflect.struct_fields_zipped(Config)

    for field in fields {
        value := reflect.struct_field_value(config, field)
        key := strings.clone(field.name)
        if field.tag == "color" {
            section[key] = fmt.aprintf("%#x", value)
        } else {
            section[key] = fmt.aprintf("%v", value)
        }
    }

    ini_map[""] = section

    save_ini(ini_map)
}
