# LinkedIn — Meeting Noter

**Attach:** `brag.mp4` (20s, landscape). Put the links in the first comment, not the body.

---

## Post

I run back-to-back calls most of the week. By Thursday I couldn't tell you what we decided
on Monday — and neither could Claude, because it was never in the room.

So I built the thing that fixes both.

Meeting Noter records a call on my Mac and transcribes it locally with whisper.cpp. Every
meeting lands in a plain folder as the recording, a timecoded transcript with speaker
labels, and a summary.md with topics, decisions and action items.

Two of those are just text. So I point Claude Code at the folder and ask "what did we
decide about the migration, and who owns the rollback?" — and it answers from the actual
meetings instead of from my memory. Every call I record turns into context an agent can
read.

The summaries are written by Claude Code too: `claude -p` over the transcript. One click
turns one into a message I paste into Slack, so the team gets the notes without me
rewriting them.

Nothing is uploaded. whisper.cpp is compiled into the app and the audio never leaves the
laptop. On calls where people say real things about real projects, that mattered to me more
than any feature.

I've stopped trying to remember which call something was decided on. It's in the folder —
for me, for the team, and for Claude.

Free, open source, macOS. Link in the comments.

---

## First comment

Site and 20-second demo: https://deemiles.github.io/meeting-noter
Source (MIT): https://github.com/deemiles/meeting-noter

Needs macOS 26 on Apple Silicon. Transcription works on its own — summaries need Claude
Code installed. Ukrainian, English, Spanish, German and Russian.

---

## Notes

- Hook is the first two lines: they have to land before LinkedIn's "see more" fold.
- The post is about the workflow, not about how the app was built — no release counts,
  line counts or war stories.
- Links stay out of the body: LinkedIn suppresses reach on posts with external links.
