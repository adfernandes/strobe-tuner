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

import "core:c/libc"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:path/filepath"
import "core:sort"
import "core:strings"


import "../core"

guitar_std_notes: [6]string = {"E2", "A2", "D3", "G3", "B3", "E4"}
ukulele_std_notes: [4]string = {"G4", "C4", "E4", "A4"}
window_bg_color: u32 = 0x40414AFF
strobe_bg_color: u32 = 0x15161AFF


INTERVAL_OPTIONS: [3][MAX_INTERVALS]f32 : {
    {1, 2, 4, 0, 0, 0, 0, 0},
    {1, 1.5, 2, 0, 0, 0, 0, 0},
    {1, 2, 3, 0, 0, 0, 0, 0},
}


// Add gui controls to choose strobe colors
COLOR_CONTROLS :: false

// Show the signal stats and NSDF plots, e.g. `odin run app -debug -define:DEBUG_STATS=true`
DEBUG_STATS :: #config(DEBUG_STATS, false)

run_app :: proc(config: ^Config) {
    target_freq_hz: f32 = config.target_freq_hz

    freq_estimation_active := false

    pitch_info := core.PitchInfo{}
    last_good_pitch_info := core.PitchInfo{}

    // Note detected by the auto-correlation method
    // FIXME: assigning a dummy cents value for undefined note
    detected_note := core.Note {
        cents = -1,
    }

    // Target note for tuning via the strobe effect
    target_note := core.Note{}

    // A newly detected note must be seen several times in a row before the strobe switches to it,
    // otherwise a single noisy detection of a decaying note resets the strobe.
    candidate_note := core.Note {
        cents = -1,
    }
    candidate_count := 0

    // Save target note to config when exiting the app
    defer config.target_freq_hz = target_note.frequency

    if !gfx_init(1200 when DEBUG_STATS else STROBE_WIDTH, 800 if COLOR_CONTROLS else 532, APP_NAME) do return
    defer gfx_shutdown()

    init_fonts()
    defer destroy_fonts()

    load_texture_atlas()
    defer unload_texture_atlas()

    //  --------------------------------------------------------------------------------------------

    phase_comparator := core.init_phase_comparator(
        target_freq_hz,
        f32(config.samplerate),
        config.strobe_intervals[:],
        config.strobe_mode,
        config.noise_floor_snr_db_threshold,
    )
    defer core.destroy_phase_comparator(phase_comparator)


    strobe_display := init_strobe_display(
        get_strobe_colors(config),
        strobe_bg_color,
        config.strobe_display_type,
    )
    defer destroy_strobe_display(&strobe_display)


    // TODO: update pitch detector when config changes
    pitch_detector := core.init_pitch_detector(
        config.samplerate,
        config.pitch_detect_fft_size,
        config.pitch_detection_clarity_high,
        config.pitch_detection_clarity_low,
        config.pitch_detection_min_snr_db,
        config.noise_floor_snr_db_threshold,
        config.rms_quiet_threshold,
    )
    defer core.destroy_pitch_detector(&pitch_detector)


    ok, audio_capture := init_audio_capture(u32(config.samplerate), config.highpass_cutoff_hz)
    if !ok do return
    defer destroy_audio_capture(audio_capture)


    register_audio_node(audio_capture, &pitch_detector)
    register_audio_node(audio_capture, phase_comparator)
    start_audio_capture(audio_capture)

    core.set_phase_comparator_freq(
        phase_comparator,
        target_freq_hz,
        config.pitch_standard,
        config.strobe_speed,
        config.speed_multiplier,
        config.strobe_mode,
    )

    target_note = core.find_note(target_freq_hz)


    // --- GUI CONTROLS ----------------------------------------------------------------------------

    audio_device_dropdown_index: int = 0
    audio_devices: [dynamic]GuiOption = {}
    defer delete(audio_devices)

    for i in 0 ..< audio_device_count(audio_capture) {
        append(&audio_devices, GuiOption{i, audio_device_name(audio_capture, i)})
    }
    audio_device_dropdown_index = int(audio_capture.active_device)

    selected_note_idx := 0
    audio_device_dropdown_active := false
    tuning_preset_dropdown_active := false


    note_low_state := false
    note_high_state := false


    strobe_speed_slider_value := config.strobe_speed
    tuning_preset_choice := int(config.tuning_preset)
    color1 := hex(config.strobe_color_1)
    color2 := hex(config.strobe_color_2)

    interval_options := INTERVAL_OPTIONS
    config_changed := false


    // ---------------------------------------------------------------------------------------------


    // ------------------------------------------------
    //                   MAIN LOOP
    // ------------------------------------------------


    for !gfx_should_close() {

        if key_pressed(.R) {
            config_changed = true
            fmt.println("Reset config to defaults")
            config^ = get_config_defaults()
        }

        if key_pressed(.X) {
            config.use_phase_average = !config.use_phase_average
        }

        super_key_down := key_down(.LEFT_SUPER) || key_down(.RIGHT_SUPER)
        pref_key_combo := super_key_down && key_pressed(.COMMA)
        if pref_key_combo {
            shift_key_down := key_down(.LEFT_SHIFT) || key_down(.RIGHT_SHIFT)

            // [Cmd + Shift + ,] - Reload config
            if shift_key_down {
                config^ = load_config()
                config_changed = true

                // [Cmd + ,] - Open config editor
            } else {
                // TODO: support windows & linux
                when ODIN_OS == .Darwin && !IOS {
                    config_path := get_config_path()
                    defer delete(config_path)
                    libc.system(fmt.ctprintf("open -a TextEdit \"%s\"", config_path))
                }
            }
        }

        if config_changed {
            strobe_speed_slider_value = config.strobe_speed
            tuning_preset_choice = int(config.tuning_preset)
            set_strobe_colors(&strobe_display, get_strobe_colors(config))
            core.set_phase_comparator_intervals(phase_comparator, config.strobe_intervals[:])
            core.set_phase_comparator_freq(
                phase_comparator,
                target_note.frequency,
                config.pitch_standard,
                config.strobe_speed,
                config.speed_multiplier,
                config.strobe_mode,
            )
            config_changed = false // !!!!
        }


        tuning_notes: []string
        if config.tuning_preset == .UKULELE_STD do tuning_notes = ukulele_std_notes[:]
        if config.tuning_preset == .GUITAR_STD do tuning_notes = guitar_std_notes[:]

        pitch_info = core.run_pitch_detection(&pitch_detector, pitch_info)

        // Count consecutive detections of the same note, only for new measurements.
        // Medium clarity detections count too, a short pluck may only be "strong" briefly,
        // but the switch itself still needs a strong detection (see below).
        if pitch_info.fresh {
            if pitch_info.is_weak_pitch {
                candidate_count = 0
            } else if candidate_note.cents == pitch_info.detected_note.cents {
                candidate_count += 1
            } else {
                candidate_note = pitch_info.detected_note
                candidate_count = 1
            }
        }
        note_confirmed := candidate_count >= config.note_switch_confirmations

        // Keep previous measurement if there is no detected note
        if pitch_info.is_strong_pitch {
            last_good_pitch_info = pitch_info
            if note_confirmed && detected_note.cents != pitch_info.detected_note.cents {
                is_octave := core.octave_apart(detected_note, pitch_info.detected_note)
                detected_note = pitch_info.detected_note
                target_note = detected_note

                // Keep the same strobe target, this is useful for some strings on guitars/basses
                // where note rings out as a harmonic.
                if config.prevent_strobe_octave_jumps && is_octave && freq_estimation_active {
                    // DO NOTHING
                } else {
                    if config.note_detection_mode == .AUTO {
                        core.set_phase_comparator_freq(
                            phase_comparator,
                            target_note.frequency,
                            config.pitch_standard,
                            config.strobe_speed,
                            config.speed_multiplier,
                            config.strobe_mode,
                        )
                    }
                }
            }
            freq_estimation_active = true
        }

        if pitch_info.is_weak_pitch {
            freq_estimation_active = false
        }

        // Keyboard arrow navigation for choosing target notes manually
        if config.note_detection_mode == .MANUAL {
            prev_target_note := target_note

            if config.tuning_preset == .CHROMATIC {
                if key_pressed(.UP) {
                    target_note = core.octave_up(target_note)
                } else if key_pressed(.DOWN) {
                    target_note = core.octave_down(target_note)
                } else if key_pressed(.LEFT) {
                    target_note = core.prev_chromatic_note(target_note)
                } else if key_pressed(.RIGHT) {
                    target_note = core.next_chromatic_note(target_note)
                }
            } else {
                is_pressed := false
                if key_pressed(.LEFT) {
                    selected_note_idx -= 1
                    is_pressed = true
                } else if key_pressed(.RIGHT) {
                    selected_note_idx += 1
                    is_pressed = true
                }

                if is_pressed {
                    selected_note_idx = selected_note_idx %% len(tuning_notes)
                    selected_note := tuning_notes[selected_note_idx]
                    target_note, ok = core.new_note(selected_note)
                }
            }

            if prev_target_note != target_note {
                core.set_phase_comparator_freq(
                    phase_comparator,
                    target_note.frequency,
                    config.pitch_standard,
                    config.strobe_speed,
                    config.speed_multiplier,
                    config.strobe_mode,
                )
            }
        }

        // TODO: explanation
        out_of_range := detected_note.cents != target_note.cents

        pitch_cents_err := core.cents_deviation(pitch_info.detected_freq, target_note.frequency)

        // Ignore return values - the NSDF provides a steadier Hz/Cents response
        core.run_phase_detection(phase_comparator, config.use_phase_average)


        if key_pressed(.TAB) {
            if config.strobe_display_type == .CURVED_TRACKS {
                config.strobe_display_type = .SPINNING_WHEEL
            } else {
                config.strobe_display_type = .CURVED_TRACKS
            }
        }

        if key_pressed(.G) {
            // Cycle through the glow presets, OFF is first so wrap around to the start
            config.strobe_glow = GlowPreset((int(config.strobe_glow) + 1) % len(GlowPreset))
        }

        if key_pressed(.I) && config.strobe_mode == .HARMONIC_MODE {
            config.strobe_intervals_index += 1
            if config.strobe_intervals_index >= len(interval_options) do config.strobe_intervals_index = 0
            config.strobe_intervals = interval_options[config.strobe_intervals_index]
            core.set_phase_comparator_intervals(phase_comparator, config.strobe_intervals[:])
            core.set_phase_comparator_freq(
                phase_comparator,
                target_note.frequency,
                config.pitch_standard,
                config.strobe_speed,
                config.speed_multiplier,
                config.strobe_mode,
            )
        }

        layout := compute_layout(gfx_window_size(), gfx_safe_area())

        // Draw the GUI controls
        gfx_begin_frame(hex(window_bg_color))
        defer gfx_end_frame()
        {

            // TODO
            // when the detected note is too far away from the target, set a fixed spinning rate and attenuate strobe display ???
            draw_strobe_display(
                &strobe_display,
                layout.strobe,
                layout.strobe_scale,
                phase_comparator,
                out_of_range,
                config,
            )

            if freq_estimation_active {
                note_low_state = core.schmitt_trigger_neg(note_low_state, pitch_cents_err, -8, -10)
                note_high_state = core.schmitt_trigger(note_high_state, pitch_cents_err, 8, 10)

                arrow_y := layout.strobe_top + 10
                if note_low_state do draw_text(font_store.medium_32, "◀", {layout.strobe.x + 10, arrow_y}, 16, 0, hex(0x82E2FFFF))
                else if note_high_state do draw_text(font_store.medium_32, "▶︎", {layout.strobe.x + layout.strobe.width - 22, arrow_y}, 16, 0, hex(0x82E2FFFF))
            }


            // -------------------------------------------------------------------------------------

            draw_note(target_note, layout.note, freq_estimation_active)

            draw_measurements(
                layout.measurements,
                pitch_info,
                last_good_pitch_info,
                freq_estimation_active,
                out_of_range,
            )


            // -------------------------------------------------------------------------------------


            // Choose new audio input
            if audio_devices[audio_device_dropdown_index].id != audio_capture.active_device {
                switch_audio_device(audio_capture, audio_devices[audio_device_dropdown_index].id)
                core.flush_audio_capture_ringbuffer(&pitch_detector)
                core.reset_noise_floor(&pitch_detector)
                core.flush_audio_capture_ringbuffer(phase_comparator)
                core.reset_phase_noise_floor(phase_comparator)
            }

            setup_strobe_display(&strobe_display, config.strobe_display_type)
            strobe_mode, strobe_mode_changed := gui_strobe_mode_toggle(
                layout.strobe_mode,
                config.strobe_mode,
            )
            if strobe_mode_changed {
                config.strobe_mode = strobe_mode
                core.set_phase_comparator_freq(
                    phase_comparator,
                    target_note.frequency,
                    config.pitch_standard,
                    config.strobe_speed,
                    config.speed_multiplier,
                    config.strobe_mode,
                )
            }


            note_detection_mode, note_detection_mode_changed := gui_note_detection_mode_toggle(
                layout.detection_mode,
                config.note_detection_mode,
            )

            if !note_detection_mode_changed && key_pressed(.SPACE) {
                note_detection_mode = .MANUAL if note_detection_mode == .AUTO else .AUTO
                note_detection_mode_changed = true
            }

            if note_detection_mode_changed {
                config.note_detection_mode = note_detection_mode

                // Select the note based on auto-detected note
                if note_detection_mode == .MANUAL {
                    for note_label, i in tuning_notes {
                        opt_note, ok := core.new_note(note_label)
                        if ok && opt_note.cents == target_note.cents {
                            selected_note_idx = i
                            break
                        }
                    }
                }
            }

            gui_speed_slider(layout.speed_slider, &strobe_speed_slider_value)
            if strobe_speed_slider_value != config.strobe_speed {
                config.strobe_speed = strobe_speed_slider_value
                core.set_phase_comparator_speed(phase_comparator, strobe_speed_slider_value)
            }

            // iOS routes the input itself: built-in mic, headset or an audio interface
            when !IOS {
                // TODO: add refresh button to show newly connected devices
                audio_device_dropdown_active = gui_dropdown(
                    layout.audio_device,
                    240,
                    audio_devices[:],
                    &audio_device_dropdown_index,
                    audio_device_dropdown_active,
                    left_pad = 32,
                )

                // microphone icon
                mic := layout.audio_device + {8, 4}
                draw_texture(texture_atlas, {96, 192, 32, 32}, {mic.x, mic.y, 16, 16})
            }

            if config.note_detection_mode != .AUTO {
                tuning_preset_dropdown_active = gui_dropdown(
                    layout.tuning_preset,
                    140,
                    {{0, "CHROMATIC"}, {1, "GUITAR STD"}, {2, "UKULELE STD"}},
                    &tuning_preset_choice,
                    tuning_preset_dropdown_active,
                )
                config.tuning_preset = TuningPreset(tuning_preset_choice)
            }

            gui_feedback_button(layout.feedback)


            when COLOR_CONTROLS {
                color_picker({20, 500, 200, 200}, &color1)
                config.strobe_color_1 = to_hex(color1)
                draw_text(
                    font_store.medium_32,
                    fmt.ctprintf("%x", config.strobe_color_1),
                    {20, 480},
                    16,
                    0,
                    LIGHTGRAY,
                )

                color_picker({300, 500, 200, 200}, &color2)
                config.strobe_color_2 = to_hex(color2)
                draw_text(
                    font_store.medium_32,
                    fmt.ctprintf("%x", config.strobe_color_2),
                    {300, 480},
                    16,
                    0,
                    LIGHTGRAY,
                )

                set_strobe_colors(&strobe_display, {config.strobe_color_1, config.strobe_color_2})
            }


            // Draw input level
            {
                meter := layout.level_meter
                draw_rect(meter, {60, 3}, hex(strobe_bg_color))
                draw_rect(
                    meter,
                    {60 + clamp(pitch_info.rms_dbfs, -60, 0), 3},
                    hex(0x82E2FFFF),
                )

                when DEBUG_STATS {
                    floor_level := core.dbfs(pitch_info.noise_floor)
                    draw_rect(meter + {0, 4}, {60, 3}, hex(strobe_bg_color))
                    draw_rect(meter + {0, 4}, {60 + floor_level, 3}, PURPLE)

                    draw_text(
                        font_store.medium_24,
                        fmt.ctprintf("RMS %.1f", pitch_info.rms_dbfs),
                        layout.stats + {130, 0},
                        12,
                        0,
                        hex(0xFBFBFBFF),
                    )

                    draw_text(
                        font_store.medium_24,
                        fmt.ctprintf("NF %.1f", floor_level),
                        layout.stats + {130, 15},
                        12,
                        0,
                        hex(0xFBFBFBFF),
                    )

                    draw_text(
                        font_store.medium_24,
                        fmt.ctprintf("SNR %.1f", pitch_info.snr_db),
                        layout.stats + {130, 30},
                        12,
                        0,
                        hex(0xFBFBFBFF),
                    )
                }
            }

            when DEBUG_STATS {

                draw_text(
                    font_store.medium_24,
                    fmt.ctprintf("Band SNR %.1f", phase_comparator.bands[0].snr_db),
                    layout.stats,
                    12,
                    0,
                    hex(0xFBFBFBFF),
                )

                draw_text(
                    font_store.medium_24,
                    fmt.ctprintf("Band NF %.1f", core.dbfs(phase_comparator.bands[0].noise_floor)),
                    layout.stats + {0, 15},
                    12,
                    0,
                    hex(0xFBFBFBFF),
                )


                draw_text(
                    font_store.medium_32,
                    fmt.ctprintf("Clarity %.3f", pitch_info.clarity),
                    {500, 10},
                    16,
                    0,
                    hex(0xFBFBFBFF),
                )
                if pitch_info.is_strong_pitch {
                    draw_text(
                        font_store.medium_32,
                        fmt.ctprintf("strong"),
                        {600, 10},
                        16,
                        0,
                        ORANGE,
                    )

                }
                if pitch_info.is_weak_pitch {
                    draw_text(
                        font_store.medium_32,
                        fmt.ctprintf("weak"),
                        {600, 10},
                        16,
                        0,
                        PURPLE,
                    )
                }

                draw_nsdf(
                    Rect{520, 40, 660, 200},
                    &pitch_detector.nsdf,
                    pitch_info.nsdf_peak,
                    font_store.medium_24,
                )

                draw_freq_plot(
                    Rect{520, 300, 660, 200},
                    &pitch_detector.nsdf,
                    font_store.medium_24,
                )
            }
        }
    }
}
