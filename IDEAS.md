# Ideas

Features and code changes that aren't planned yet. Nothing here is decided.

## Steady rotation far from a locked note

Behind a flag, in locked mode only. Tuning up a new string with the note locked to low E, the string
starts far below the note and wobbles on the way up. The strobe has nothing steady to show there, and
it's hard to tell how far there is to go.

Far out, show a simulated rotation at a steady rate in the right direction, and blend it into the
real strobe as the string comes within about 50 to 100 cents.

- The band's window is 25 cents a bin, so the lock-in hears the string about 20 dB down at 50 cents
  and not at all past 75. The direction and distance out there have to come from the pitch detection,
  like the arrows next to the note.
- The blend could follow the band's SNR, which rises as the string comes into the window.
- A constant rate reads as "keep going", a rate that follows the distance would jump around with the
  wobble it is meant to hide.
- The handover is the hard part, the simulated stripes and the real ones have to meet without a
  jump in phase or speed. May not be worth it if it can't be made seamless.

## In-tune cues

One setting, all optional.

- Green note name within the tolerance, the strobe itself stays unchanged.
- A short beep once the note holds in the window for about 300 ms. The detection ignores the input
  briefly so the mic doesn't read the beep.
- A haptic tap as a quieter alternative to the beep.

## Audible beating mode

A tone or click through headphones whose rate follows the pitch error and stops when in tune. Also the
path to real VoiceOver support later.

## Piano stretch tuning

## Temperaments and sweetened tunings

## Custom offsets in two slots

For intonation compromises, like tuning a ukulele's E down about 5¢ so the fretted chords sound right.
The strobe stops at the offset note, so no one has to judge a slow drift by eye. No presets, no editor
and no settings page, everything is on the main screen.

- **Slot switch** `Off · 1 · 2` in the bottom bar, where the audio input dropdown used to be. The
  active slot is the one being edited and changes save automatically. Off is standard tuning, the
  slots keep their offsets.
- **± buttons** next to the cents readout while a note is locked, 0.5¢ a step. The readout never gets
  steady enough to capture an offset from it, so offsets are set by number.
- **One offset per exact note** (E4, not every E). Each string is its own note.
- **Offsets apply unlocked too.** The detected note's target moves with its offset.
- **Visible:** "E4 −5¢" under the note name and a dot on the offset notes in the ruler.
- **Clearing:** long-press a slot, then confirm. Setting a note back to 0 resets that note.
