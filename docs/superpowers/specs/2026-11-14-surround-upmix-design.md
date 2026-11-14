# Simulated 5.1 surround for Ororo on Apple TV: design

Date: 2026-11-14. Status: approved by Max, then revised after a four-way review (see *Review findings*).

## Intent

Max watches Ororo on an Apple TV connected (through the TV, over HDMI ARC or optical) to a
Sony HT-RT4 5.1 system. Ororo's audio comes out of the front speakers only. He wants
"proper cinema sound": all five speakers and the subwoofer working during Ororo playback.

Why it happens today: every Ororo stream carries stereo AAC only (measured, see *What the
spike proved*). The app passes it through untouched, so only front left and right play.
The Sony link can carry stereo or Dolby Digital 5.1 and nothing else, so the rear speakers
only get sound when the Apple TV is handed real 5.1 audio to encode.

## Goals

- During Ororo playback on a 5.1 output, the app delivers a real 5.1 audio track
  (front left/right, centre, two surrounds, LFE) derived from the stereo original.
- Dialogue is anchored in the centre; ambience and music width reach the surrounds; bass
  reaches the subwoofer (through the Sony's own bass management of the main channels,
  not through a loud LFE channel: see *Upmix character*).
- Everything the player does today keeps working: native transport controls, the system
  subtitle menu, resume, next episode, stall and expired-URL recovery.

## Non-goals

- True discrete surround. The source is stereo; this is an upmix and is labelled as such.
- The iOS app. It keeps the original audio. (Builder's call to share code where free.)
- Dolby Atmos, 7.1, height channels.
- Offline downloads (unused this round).

## Anti-goals (a failure even if it "works")

- Changing any system or receiver setting, or affecting any other app. Max ruled this out.
  (The Apple TV → TV → Sony chain already delivers 5.1 from other apps that have it, so
  no setting needs to change.)
- Audible clicks, gaps or pumping at segment boundaries, after seeks, or on resume.
- Lip-sync error. Audio must stay within ±20 ms of where the original audio would be.
- Playback that fails or stalls because the upmix failed. The original audio is always the
  fallback.
- Logging, persisting or exposing the signed stream URL (existing rule, unchanged).
- A CI workflow or other infrastructure nobody asked for.

## Constraints found

- Streams are HLS, unencrypted fragmented MP4, with **audio in separate renditions**
  (`#EXT-X-MEDIA:TYPE=AUDIO` groups), AAC-LC stereo, 48 kHz, 1024-sample frames, about 4 s
  per segment. Episodes use one audio group per variant (`aud1`…`aud3`); movies use
  `audio_sd` / `audio_hd`. Video segments are separate (H.264) and are not touched.
- `MTAudioProcessingTap` / `AVAudioMix` cannot be used: unsupported on HLS and unable to
  change the channel count.
- `AVAssetResourceLoader` custom schemes (the existing `ororo-subs://` seam) can serve
  playlists but not media segments. Generated audio must be served over HTTP from a
  loopback server inside the app.
- The Apple AAC encoder adds 2112 samples of delay; segments are encoded independently
  (the player seeks and fetches out of order), so continuity has to be engineered.
- Deployment target is tvOS 26; Swift 6 language mode; no third-party dependency is
  needed and none should be added.
- 5.1 only reaches the Sony if the Apple TV's audio output is Dolby Digital 5.1
  (Settings → Video and Audio → Audio Format). The app cannot set this; it can only read
  how many channels the current output offers. Max confirmed other apps already produce
  surround on the Sony where the title supports it, so the chain works today. The exact
  setting value was not read back; the first hardware check confirms it.
- The device is an Apple TV 4K (generation not stated). There should be headroom for a
  better-than-passive upmix, but speed is unmeasured on it: measure on the device before
  committing to an expensive algorithm, and treat "generation cannot keep up" as one of
  the failures that falls back to original audio.

## Approaches

1. **Generate a 5.1 audio rendition inside the existing playlist rewrite (chosen).** The
   app already serves a synthetic multivariant playlist to inject subtitles. It also
   replaces each audio group with a rendition it generates: fetch the original audio
   segment, decode, upmix to 5.1, re-encode as 5.1 AAC, repackage as fMP4, serve from a
   loopback HTTP server. Keeps `AVPlayer` and everything built on it. Cost: an audio
   pipeline to write and tune; risk concentrated in segment-boundary continuity.
2. **Replace the player with an FFmpeg-based engine.** Upmix is a stock filter, but the
   native player UI, system subtitle menu and the recent black-screen fixes are thrown
   away, with LGPL/GPL obligations and a much larger binary.
3. **Mute the video player and run a parallel audio player.** Same decoding work as 1,
   plus two clocks to keep in sync through every pause, seek and stall.

Max picked approach 1 ("let's try Option 1 first").

## What the spike proved (throwaway, not in the repo)

Run on macOS and inside the Apple TV 4K simulator (tvOS 27.2 SDK) against a live episode:

- Decoding the stereo AAC, upmixing, encoding 6-channel AAC with `AVAudioConverter`
  (layout `kAudioChannelLayoutTag_MPEG_5_1_D`) and repackaging as fMP4 works. The
  generated file reads back as 6 channels, 48 kHz, with signal in every channel.
- The init segment can be reused by patching the `mp4a` channel count and the
  AudioSpecificConfig channel configuration to 6. Segments are rebuilt as
  `moof`(`mfhd`, `traf`(`tfhd`, `tfdt`, `trun`)) + `mdat`, reusing the original track ID,
  base decode time and frame count.
- `AVPlayer` accepts a multivariant playlist whose audio group points at
  `http://127.0.0.1:<port>/…` next to Ororo's HTTPS video, reports a 6-channel audio
  track, plays, and survives a seek to 10:00.
- Cost was 45–385 ms per 4 s segment on a Mac/simulator.
- The player logged "Segment exceeds specified bandwidth for variant" because the 5.1
  audio is heavier than the stereo it replaces: `BANDWIDTH` must be raised to match.

Not yet proven: real Apple TV hardware speed; sound reaching the Sony's rear speakers;
click-free boundaries (the spike made no attempt); how the result sounds.

## Design

### Decided

- **Where it plugs in.** `SubtitlePlaylistBuilder` / `SubtitleResourceResponder` grow from
  "inject subtitles" into "author the playlist": subtitles as today, plus surround audio
  groups when surround is active. A title without subtitles also goes through the
  synthetic playlist when surround is active (today it plays the stream URL directly).
- **Every audio group is replaced, all pointing at one generated rendition** per distinct
  language and name, sourced from the audio group of the highest-bandwidth variant, with
  `CHANNELS="6"`. Sharing one rendition means a video quality switch never restarts the
  audio. Each variant's `BANDWIDTH` is raised by a flat 384 kb/s (the generated audio
  measures about 394 kb/s; over-declaring is the safe direction).
- **Pre-flight.** Before the rewritten playlist is handed to the player, the app fetches
  and validates the audio media playlist, the init segment and the first segment. If
  the audio is anything other than unencrypted fMP4 stereo AAC-LC at 48 kHz with
  1024-sample frames in one continuous VOD playlist, the playlist is left untouched and
  the title plays its original audio with no reload at all.
- **Loopback server.** Bound to 127.0.0.1 on an ephemeral port, alive for one playback
  item, with an unguessable per-item path prefix. It serves the audio media playlists,
  the patched init segment and generated segments. Nothing is written to disk; a small
  in-memory cache covers re-requests.
- **Segment continuity.** Each segment is decoded and encoded with enough audio from its
  neighbours (pre-roll and post-roll) that the packets it emits are the ones a continuous
  encode would have produced, and upmix filter state is warmed the same way. The fixed
  encoder delay is compensated to within one 64-sample remainder (1.3 ms), constant for
  the whole title. Verified by experiment: pre-roll of 2 packets or more and post-roll of
  exactly 2 or more bring joins down to ordinary codec noise; without post-roll every
  join is a loud tick.
- **Upmix character.** Centre carries what is common to left and right (dialogue);
  surrounds carry the difference signal, decorrelated between left and right surround,
  slightly delayed and band-limited so they read as ambience rather than a second front
  pair. The LFE channel is kept nearly silent (−20 dB): the main channels keep their
  full bass and the Sony redirects it to the subwoofer, so a louder LFE would add about
  5 dB of extra bass. Overall loudness matches the original. (An earlier claim that a
  stereo downmix of the result sounds like the original was dropped: it is false for
  wide content, and stereo outputs never receive the upmix anyway.)
- **When it is active.** Surround is used only when the setting is on *and* the current
  audio output offers at least 6 channels. Otherwise the original audio plays exactly as
  today. Headphones, AirPlay to stereo devices and TV speakers therefore never get the
  upmix.
- **Setting.** One switch in Settings, "Simulated surround", on by default, persisted
  like the other settings. If the last playback found a stereo-only output, the row says
  the original sound is being used. It gives no instruction to change an Apple TV
  setting (that would be the system-wide change Max ruled out).
- **Fallback.** Unsupported audio is caught by the pre-flight and never starts surround.
  If the audio path fails later (a segment that cannot be parsed, decoded or encoded;
  generation too slow to keep the player fed), the player shows its normal loading
  state, refetches the title and continues from the current position with original
  audio. No error screen. Surround then stays off until the player is closed; if the
  cause was the device being too slow, it stays off until the app is relaunched. The
  session's own automatic recovery after a stall or stream failure also retries without
  surround, so surround can never be what turns one failure into an error screen.
  A network error while fetching original audio is *not* a surround failure: it is
  handled like any network trouble today.
- **App lifecycle.** When the app becomes active again, the loopback server is checked
  and, if it stopped, restarted on the same port so the player's playlists stay valid.
  If it cannot be restarted, that is a surround failure (above).
- **Debug signals (debug builds only).** Two test signals can replace the upmix output:
  a speaker identification sequence (centre, front left, front right, rear left, rear
  right, subwoofer; channel *k* plays *k* beeps) and a steady tone that makes any join
  defect an obvious tick. They are how the hardware checkpoints verify channel order
  and click-free joins.
- **Build order.** Segment continuity, the fallback and the debug signals are in place
  before Max's first run on the Apple TV (an experiment showed the bare build would
  tick loudly every 4 s and could not prove which speaker is which). The first run
  still uses the placeholder mix and measures generation speed on the device. The real
  upmix and the setting come after.
- **Titles with their own 5.1 (added after Checkpoint A).** Some Ororo titles carry a real
  multichannel rendition alongside the default stereo one. When the output offers at least
  6 channels, the player selects the rendition with the most channels (same language only; the
  language is never switched). This is real audio, not simulation, so it does not depend on the
  "Simulated surround" setting. The upmix already declines such titles.
- **App configuration.** The tvOS Info.plist gains the local-networking transport
  exception needed to load `http://127.0.0.1`.

### Left to the builder

- Module boundaries. Suggested: pure, testable pieces (fMP4 parse/build, init patch,
  playlist authoring, upmix DSP) in `OroroCore/Playback`; the converter and server in
  `OroroFeatures/Player`.
- The exact upmix algorithm (passive matrix with steering, or frequency-domain), filter
  designs, delay and gains, within the character above. Expect a tuning round by ear on
  the Sony.
- Pre-roll and post-roll lengths, concurrency and look-ahead, cache size.
- Encoded bitrate (the spike used 384 kb/s).
- How the output channel count is observed and how route changes mid-playback are
  handled (acceptable: decided at load time, re-evaluated on the next load).

## Acceptance

Automated:
- fMP4 parse → build round-trips; init patch yields a 6-channel sample entry.
- Playlist authoring: every audio group replaced, `CHANNELS="6"`, bandwidth raised,
  subtitles still injected, titles without subtitles covered.
- Continuity: segments generated independently and concatenated match the true upmix of
  the continuous source; error near the joins is no worse than error elsewhere.
- Channel identity: each of the six channels carries its own signal through encode,
  repackaging and playback order.
- Loudness: total power of the upmix stays within a stated tolerance of the stereo input.
- Pre-flight: every unsupported audio shape leaves the playlist untouched.
- Fallback: an injected audio failure yields one reload with original audio at the same
  position and no error screen; a late failure from a previous title is ignored.

On Max's Apple TV and Sony HT-RT4 (only he can run this):
- The Sony reports a Dolby Digital 5.1 input during Ororo playback and sound comes from
  the rear speakers, centre and subwoofer.
- No clicks across 10 minutes of playback, three seeks, a pause/resume and a next-episode
  transition.
- Lip sync looks right; subtitles, resume and the transport bar behave as before.
- Generating a segment takes well under real time (target: under 25% of its duration).
- With the setting off, or on a stereo output, audio is the original.
- The speaker identification sequence comes out of the right speakers in the right order.
- After the Apple TV sleeps for 15 minutes mid-episode, playback resumes.

## Review findings (2026-11-14)

Four independent reviews of this spec and the plan, one of which ran experiments on a
Mac. What they established and what changed:

- Measured: the AAC decoder returns exactly n × 1024 frames with no priming removed and
  only the first packet's output is unreliable; encoder delay is 2112 samples for
  6 channels; pre-roll 2+ and post-roll 2+ give joins at codec-noise level; the encoder
  averages about 394 kb/s at a 384 kb/s setting; patching only the `mp4a` channel count
  and the AudioSpecificConfig yields a valid 5.1 init segment; loopback IP-literal URLs
  are outside App Transport Security.
- Changed because of the reviews: pre-flight validation; the fallback rerouted through
  the session's reload instead of a second reload inside the engine; one shared audio
  rendition; near-silent LFE; the downmix claim dropped; neutral Settings wording;
  server restart on return to the foreground; debug signals made mandatory; continuity
  and fallback moved before the first hardware run.
- Still unproven until the hardware checkpoints: that tvOS reports 6 output channels on
  Max's chain and sends the track to the Sony as Dolby Digital 5.1; generation speed on
  the Apple TV; whether the listener survives sleep; how the upmix sounds (a fixed
  matrix narrows the front stage for hard-panned sounds; expect a tuning round).
