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


package core

import "core:math"
import "core:testing"

MIN_RMS_TRACKABLE :: 1e-6

NOISE_FLOOR_TIME_S :: 0.5
NOISE_FLOOR_RISE_DB_PER_S :: 1.0
NOISE_FLOOR_WARMUP_S :: 1.0 // follows ungated at first, the level isn't known yet
MIN_NOISE_FLOOR :: 1e-6 // -120 dB, a level of digital silence doesn't pull it down to zero


// The level of the background noise, of the whole signal for the pitch detector or of one strobe band.
// It follows the level in dB while nothing louder plays, and pauses when the SNR is above the threshold,
// only creeping up so it catches up with a noisier room, slow enough that a sustained note barely moves it.
NoiseFloor :: struct {
    level:            f32, // 0 until the first update
    warmup:           f32, // seconds left of following the level ungated
    snr_threshold_db: f32, // louder than this over the floor counts as something playing
}

init_noise_floor :: proc(snr_threshold_db: f32) -> NoiseFloor {
    return {warmup = NOISE_FLOOR_WARMUP_S, snr_threshold_db = snr_threshold_db}
}

// Learn it again, e.g. for another input device
reset_noise_floor :: proc(self: ^NoiseFloor) {
    self.level = 0
    self.warmup = NOISE_FLOOR_WARMUP_S
}

// Updates with the level measured over the last dt seconds, returns its SNR over the floor before the update.
// Without warming_up the warmup time doesn't run out, e.g. while the window is still on the silence it
// starts out with.
update_noise_floor :: proc(self: ^NoiseFloor, level: f32, dt: f32, warming_up := true) -> (snr_db: f32) {
    level := max(level, MIN_NOISE_FLOOR)

    if self.level == 0 {
        self.level = level
        return 0
    }

    snr_db = 20 * math.log10(level / self.level)

    if warming_up do self.warmup = max(self.warmup - dt, 0)

    if self.warmup > 0 || snr_db < self.snr_threshold_db {
        // Smooth in dB, the level of the noise in a single bin dips deep now and then
        alpha := 1 - math.exp(-dt / NOISE_FLOOR_TIME_S)
        self.level *= math.pow(10, alpha * snr_db / 20)
    } else {
        self.level *= math.pow(10, NOISE_FLOOR_RISE_DB_PER_S * dt / 20)
    }
    self.level = max(self.level, MIN_NOISE_FLOOR)

    return snr_db
}


@(test)
test_noise_floor :: proc(t: ^testing.T) {
    DT :: 0.05
    floor := init_noise_floor(10)

    // Learns the background
    for _ in 0 ..< 100 do update_noise_floor(&floor, 0.001, DT)
    testing.expectf(t, abs(floor.level - 0.001) < 1e-5, "background, got %v", floor.level)

    // A loud note stands out and barely moves it, only the slow creep
    snr: f32
    for _ in 0 ..< 20 do snr = update_noise_floor(&floor, 0.1, DT)
    testing.expectf(t, snr > 35, "note SNR, got %v dB", snr)
    rise_db := 20 * math.log10(floor.level / 0.001)
    testing.expectf(t, abs(rise_db - NOISE_FLOOR_RISE_DB_PER_S * 20 * DT) < 0.01, "rise, got %v dB", rise_db)

    // Back down after the note
    for _ in 0 ..< 200 do update_noise_floor(&floor, 0.001, DT)
    testing.expectf(t, abs(floor.level - 0.001) < 1e-5, "after the note, got %v", floor.level)
}
