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


#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Output fragment color
out vec4 finalColor;

const float TAU = radians(360);

// Uniforms
uniform vec4 bounding_rect;
uniform float curvature_radius;
uniform int strobe_blur;
uniform vec3 color_a;
uniform vec3 color_b;

uniform float time_stretch;
uniform float phase;
uniform float phase_step; // change of phase since the previous frame
uniform int motion_blur;
uniform int glow;
uniform float lamp_spread; // angular width of the lamp hotspot in radians
uniform float amp;
uniform float norm_freq;
uniform float band_height;
uniform float err_cents;
uniform float period_count;
uniform float min_radius;
uniform float max_radius;


float generate_signal(
    float freq,
    float phase,
    float amplitude,
    float time,
    float time_stretch,
    float period_count,
    bool strobe_blur
) {
    time = time * time_stretch;

    float value = 0.0;
    float sinewave = sin(period_count * (freq * TAU * time + phase));

    if (strobe_blur) {
        value = amplitude * sinewave;
    } else {
        value = amplitude * sign(sinewave);
    }

    // convert from range -1..1 to 0..1
    value = 0.5 * value + 0.5;
    value = max(min(value, 1.0), 0.0);

    return value;
}

// Average the signal over the phase swept since the previous frame, like a camera shutter would.
// Without it the pattern aliases (wagon wheel effect) and shimmers once it moves close to
// half a period per frame.
float generate_blurred_signal(
    float freq,
    float phase,
    float phase_step,
    float amplitude,
    float time,
    float time_stretch,
    float period_count,
    bool strobe_blur
) {
    // Radians of the pattern swept during one frame
    float sweep = abs(period_count * phase_step);

    if (sweep < 0.05) {
        return generate_signal(freq, phase, amplitude, time, time_stretch, period_count, strobe_blur);
    }

    // A full period or more averages out to a flat colour, the pattern carries no information
    if (sweep >= TAU) {
        return 0.5;
    }

    // ~24 samples per period is enough to keep the average smooth even for the hard edged square wave
    const int MAX_SAMPLES = 24;
    int n = int(clamp(ceil(sweep * float(MAX_SAMPLES) / TAU), 2.0, float(MAX_SAMPLES)));

    float sum = 0.0;
    for (int i = 0; i < MAX_SAMPLES; i++) {
        if (i >= n) break;
        float t = (float(i) + 0.5) / float(n);
        sum += generate_signal(freq, phase - t * phase_step, amplitude, time, time_stretch, period_count, strobe_blur);
    }
    float value = sum / float(n);

    // Ease the last bit of contrast out, so the pattern doesn't pop when the sweep crosses a full period
    float fade = 1.0 - smoothstep(0.75 * TAU, TAU, sweep);

    return mix(0.5, value, fade);
}

float draw_curved_track(
    vec2 size,
    float thickness,
    float outer_radius,
    float feathering,
    vec2 distance
) {
    float radial_position = length(distance); // sqrt((x * x) + (y * y))
    float inner_radius = outer_radius - thickness;

    float outerCircle = smoothstep(outer_radius, outer_radius - feathering, abs(radial_position));
    float innerCircle = smoothstep(inner_radius, inner_radius - feathering, abs(radial_position));

    float donut = outerCircle - innerCircle;

    return donut;
}



void main()
{
    // Viewport resolution (extract width & height)
    vec2 size = bounding_rect.zw;

    // Position in pixels
    vec2 position = fragTexCoord * size;
    float feathering = 2; // 2 px feathering for smoothstep

    // Define the thickness of our donut shape (track), leave a gap between tracks
    // TODO: define gap in strobe display struct
    float thickness = band_height - 4;

    // Calculate the center so the circle touches the top of the viewport
    // vertically and is centered horizontally
    vec2 center = vec2(0.5 * size.x, curvature_radius);

    // This is the pixel position in terms of distance from the circle center
    vec2 distance = center - position.xy;

    // Color the pixel at position based on whether it sits in the donut shape
    float curved_track = draw_curved_track(size, thickness, curvature_radius, feathering, distance);


    // Color in the generated strobe signal

    // Current pixel angle
    float angle = atan(distance.y, distance.x);

    // Time is translated from the linear to radial
    float time = angle / TAU;

    float signal_value = generate_blurred_signal(
        norm_freq,
        phase,
        motion_blur > 0 ? phase_step : 0.0,
        amp,
        time,
        time_stretch,
        period_count,
        strobe_blur > 0
    );

    // Blend colors
    vec3 rgb = mix(color_a, color_b, signal_value);
    float alpha = curved_track;

    if (glow > 0) {
        // Emulate a lamp shining through a strobe disc, like the old Conn Strobotuners

        // Stripes drawn in color_a are the lit ones
        float lit = 1.0 - signal_value;

        // Light scattering into the dark stripes, a soft copy of the pattern (just the fundamental)
        float scatter = 1.0 - generate_blurred_signal(
            norm_freq,
            phase,
            motion_blur > 0 ? phase_step : 0.0,
            1.0,
            time,
            time_stretch,
            period_count,
            true
        );

        // Lamp hotspot, brightest around the top centre of the arcs and the middle bands
        float radial_position = length(distance);
        float radial_t = (radial_position - min_radius) / max(max_radius - min_radius, 1.0);
        float angle_offset = (angle - 0.25 * TAU) / lamp_spread;
        float hotspot = exp(-angle_offset * angle_offset - 1.5 * (radial_t - 0.45) * (radial_t - 0.45));

        float emission = clamp(lit + 0.15 * scatter, 0.0, 1.0) * mix(0.7, 1.0, hotspot);

        // Incandescent lamp, warms the lit stripes towards amber rather than burning them white
        vec3 lamp = vec3(1.0, 0.62, 0.28);
        vec3 warm = mix(color_a, lamp, 0.45 * mix(0.6, 1.0, hotspot));

        // Dark stripes still glow faintly
        rgb = mix(color_b * 0.7, warm, emission);
        rgb *= mix(0.85, 1.1, hotspot);
        rgb = min(rgb, vec3(1.0));

        // Halo spilling a few pixels past the track edges into the gaps
        float inner_radius = curvature_radius - thickness;
        float outside = max(radial_position - curvature_radius, inner_radius - radial_position);
        float halo = exp(-max(outside, 0.0) / 3.0) * step(0.0, outside) * step(outside, 8.0);
        halo *= 0.25 * emission;
        alpha = max(alpha, halo);
        rgb = mix(rgb, warm, clamp(halo * (1.0 - curved_track), 0.0, 1.0));
    }


    // Circular gradient from center to the outer edge

    // vec3 color_a = vec3(255.0, 10.0, 125.0); // pink
    // vec3 color_b = vec3(255.0, 140.0, 20.0); // orange

    // float radial_position = length(distance);
    // float gradient_position = 1.2 * (radial_position - min_radius) / (max_radius - min_radius);
    // vec3 rgb = mix(color_b / 255.0, color_a / 255.0, gradient_position);

    finalColor = vec4(rgb, alpha);
}
