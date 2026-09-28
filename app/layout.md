# Layout

`layout.odin` works out where everything goes every frame, from the window size and the safe area (in points).
A window taller than 1.3× its width gets the portrait layout, anything else the desktop one.

## Rules

- Points, not pixels. Both backends draw in points and scale to the display's pixel density.
- Lay out inside the safe area (clear of the Dynamic Island and the home indicator), but let the strobe
  background run up behind the notch so it doesn't look boxed in.
- Controls sit at the bottom of the portrait layout, within thumb reach.

## Desktop

The original fixed layout, 488×532.

## Portrait phone

```
┌──────────────────────┐
│   (safe-area top)    │  strobe background runs up behind the notch
│                      │
│   STROBE  ~50%       │  3 bands, scaled up 1–1.4× to fill half the safe area
│                      │
├──────────────────────┤
│  C₄    Hz    Cents   │  note + readout, same as desktop, tap the note to lock it
│  ◀ ▶                 │  semitone steps, only while the note is locked
│                      │
│  [HARMONIC] [ RESP ] │  strobe mode, response
│  🎤▬▬              ⚙ │  input level, settings
│  (home indicator)    │
└──────────────────────┘
```

- No mic picker, iOS routes the input itself.
- Debug stats only with `-define:DEBUG_STATS=true`.

## Settings

The cog swaps the whole window for the settings screen, the audio keeps running behind it.
Same layout on desktop and phone, a column of 44pt rows inside the safe area.

```
┌──────────────────────┐
│ Settings           ✕ │
├──────────────────────┤
│ Concert A  [- 440 +] │  pitch standard, 400–480 Hz
│ Display [Tracks|Whee]│
│ Style [Red|Min|Amb|R]│  red, minty, amber or ruby glow; custom colors stay in the config file
│ Partial labels [...] │  off, 1×, Hz, note
│ Band cents  [Off|On] │
│ Input    [🎤 device ▾]│  desktop only
│ Reset to defaults [R]│  tap twice, the first tap asks to confirm
└──────────────────────┘
```

## Icons and shapes

- Icons are Phosphor Regular glyphs (`assets/fonts/phosphor`), drawn as text at 16pt, see `font.odin` to add one.
- Pills and rounded rectangles are cut from a white circle generated at startup and tinted, see `shapes.odin`.

## Later

- Touch: tap the bands to switch between the curved tracks and the full wheel.
- Swipes on the strobe to step a locked note by semitones.
- Bigger touch targets, at least 44pt. The pill buttons are 24pt tall.
- Scale the note readout and fonts from the short side of the screen.
- Landscape and iPad.
