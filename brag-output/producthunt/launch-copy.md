# Product Hunt — Meeting Noter

## Name
Meeting Noter

## Tagline  (limit 60)

**Recommended:** On-device meeting notes for Slack, Teams and Meet

Alternatives:
- Records, transcribes and summarizes calls on your Mac
- Meeting notes that never leave your Mac

## Description  (limit 260)

Records your Slack, Teams or Meet calls, transcribes them on your Mac with whisper.cpp and
summarizes them with Claude. Mic and system audio are captured as separate tracks, so you
get speaker labels without a diarization model. Nothing is uploaded.

## Pricing
Free

## Topics
Mac · Productivity · Artificial Intelligence

## Links
- Website: https://deemiles.github.io/meeting-noter
- GitHub: https://github.com/deemiles/meeting-noter

---

## Maker's first comment

Hey Product Hunt 👋

I run back-to-back calls most of the week, and by Thursday I couldn't tell you what we
decided on Monday. Every meeting-notes tool I tried wanted the audio on their servers
first — and on calls where people say real things about real projects, I wasn't comfortable
with that.

So Meeting Noter does the whole thing on the laptop:

• Records Slack, Microsoft Teams, a Google Meet tab, or the full screen
• Transcribes locally — whisper.cpp is compiled into the app, so there's no Homebrew step
  and nothing leaves the machine
• Summarizes with the Claude CLI into topics, decisions and action items
• One click turns a summary into a message you paste straight into Slack

Two things worth pointing out:

**The mic and the system audio are two separate tracks.** They're transcribed
independently and merged by timecode, which is why you get "Me" / "Them" labels without a
diarization model. Mixing them down was the one shortcut I had to stop myself from taking —
two people on one channel interfere and recognition falls apart.

**Every call lands in a plain folder** — transcript.txt, summary.md, meta.json. So you can
point an agent at it and ask what was decided across all your meetings, not just the one
you happen to remember. That turned out to be the part I use most.

Free, MIT, macOS 26 on Apple Silicon. Signed and notarized, so it opens with a normal
double-click.

Happy to answer anything — and I'd genuinely like to hear what's missing. Windows and Linux
are the two asks I expect, and I don't have an answer for either yet.

---

## Gallery order

| # | File | Shows |
|---|---|---|
| 1 | `01-hook.png` | The claim — your calls stay on your laptop |
| 2 | `02-recording.png` | Recording a Slack call, two separate tracks |
| 3 | `03-transcript.png` | Transcript with speaker labels, done on-device |
| 4 | `04-summary.png` | Topics / decisions / action items |
| 5 | `05-slack.png` | The notes as a message ready to paste |
| 6 | `06-app.png` | The actual app window |

`thumbnail.png` — 240×240, the app icon.

## Video

Product Hunt only accepts a **YouTube URL**, not an upload. Put `brag.mp4` on YouTube
(unlisted is fine) and paste the full link — not a youtu.be short link.

## Launch checklist

- [ ] Post from a **personal** account — company accounts can't post
- [ ] Upload `brag.mp4` to YouTube, grab the full URL
- [ ] Launch at **00:01 PT** — the PH day starts then and you want the full 24 hours
- [ ] Tue–Thu usually beat Mon/Fri; weekends are quiet but less competitive
- [ ] Have the first comment ready to post the moment it goes live
- [ ] Check the download link works from a browser with a cold cache
