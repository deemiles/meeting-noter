# brag-plan — Meeting Noter

**Tone:** punchy (re-rolled from `polished` — more energy) · **Format:** landscape 1920×1080, 30fps · **Length:** 20s

## Angle

The product's own headline is the angle: **"Your calls stay on your laptop."** Every
competing tool starts by asking you to upload your audio. This one never does — whisper.cpp
is compiled into the app. That's the claim, and it's true, so lead with it.

## Hook (first 2 seconds)

Two waveforms — `system` and `mic` — talking in turns on black. No logo, no title card.
It's the product's actual mechanic: recording the two sides of a call as separate tracks
is what makes everything downstream work, and it looks like a conversation before a single
word appears.

## Highlights

1. **Two tracks, one recording.** The mic and the far end never get mixed — that's why
   speaker labels come out without a diarization model.
2. **Transcribed on the machine.** whisper.cpp inside the app bundle. Nothing uploaded.
3. **A summary you can paste.** Topics, decisions, action items — one click into Slack.

## Punchline

The real app window, the name, the URL. Restraint: it has earned the reveal by then.

## The window in the outro

It shows the same meeting the video just followed — the migration call — so the five scenes
read as one story rather than five unrelated shots. The window is the app's own layout and
palette rebuilt at 2x with English demo content: the machine's screen was locked at render
time, so a live capture was not possible, and an earlier real capture was in Ukrainian while
every caption here is English.

## Visual identity (exact, from `docs/index.html`)

- Background `#07060d`, ink `#f4f2ff`, muted `#a29fbd`, dim `#6f6b8f`
- Indigo `#6d5ef6`, violet `#a855f7` (system / "Them"), green `#34d399` (mic / "Me"), red `#ff4d5e` (recording)
- Type: SF Pro Display / Text; transcript in SF Mono — same stack the site uses
- Glass cards, indigo aurora, the same language as the app

## Storyboard

Cuts sit on a 120 BPM grid (beat = 0.5s) so the picture moves with the track. Hard cuts
through the background rather than crossfades — at this pace a fade smears two busy layouts.

| # | Scene | Secs | On screen | Line (words → min settled) |
|---|---|---|---|---|
| 1 | Hook | 0.0–3.0 | Two waveforms trade turns; headline punches in at 0.3s | *Your calls stay on your laptop.* (6 → 1.8s, settled 2.0s) |
| 2 | Record | 3.0–6.0 | Record button, rings at double speed, live timer, `system` / `mic` | *Two separate tracks. Never mixed.* (5 → 1.5s, settled 2.0s) |
| 3 | Transcribe | 6.0–10.0 | Three lines rip in from the left, speakers coloured; `whisper.cpp` chip | *Transcribed on your Mac. Nothing uploaded.* (6 → 1.8s, settled 3.0s) |
| 4 | Summarize | 10.0–14.0 | Topics → Decisions → Action items snap in; "Copied" pops | *Summarized by Claude. Ready to paste.* (6 → 1.8s, settled 2.9s) |
| 5 | Slack | 14.0–16.0 | The real `SummaryFormatter` output assembling line by line | *Pasted straight into Slack.* (4 → 1.2s) |
| 6 | Outro | 16.0–20.0 | The app window rises in showing **the same call** the video just recorded, name, URL, languages | *Meeting Noter · free & open source* |

## Sound

One piece in D minor at 120 BPM, arranged to build rather than loop:

| Bars | Section | Kit |
|---|---|---|
| 0–1.5 | Hook | none — pad and a sparse bass only |
| 1.5–3 | Record | kick enters on the cut (+6 dB) |
| 3–8 | Transcribe → Slack | kick, claps on 2 and 4, off-beat hats, eighth-note bass, arp |
| 8–10 | Outro | kit drops out, resolving Dm chord rings to the end |

Effects are tuned to the chord under them and sent through the same reverb, so they sit
inside the track: a soft D as recording starts, A/F ticks as transcript lines land, a
two-note lift on "Copied", and a low impact on each of the five cuts.
