# Audio performance and continuity review

BreakBoss requests 48 kHz and a 128-frame I/O buffer from AVAudioSession. At 48 kHz,
128 frames represent 2.67 ms. iPadOS and the selected audio route determine the actual
sample rate and buffer duration. No physical iPad timing measurements or Apple SDK build
were available in this workspace; this review does not establish a dropout-free guarantee.

## Changes made

- Normal polyphony remains 40 voices. Eight extra, preallocated voice slots preserve a
  stolen waveform for a 4 ms fade instead of immediately overwriting it. Total voice
  rendering is bounded at 48. If an extreme burst occupies all 48 slots, excess triggers
  are dropped until a tail slot becomes free. No buffer allocation occurs for stealing.
- New voices use a 0.5 ms attack ramp. This limits steps at the beginning of reversed
  sounds and arbitrary imported samples. Prepared stock assets also have boundary fades.
- Kit changes fade both normal voices and steal tails. Kit buffers remain owned for
  15 ms, longer than the 5 ms kit fade and 4 ms steal fade. Tail voices hold raw sample
  pointers, so they do not introduce audio-thread object destruction or independent
  ownership that could outlive the kit.
- The scheduler binary-searches the sorted loop ticks for the current callback window,
  expanded for BOUNCE's possible timing shift. It then uses the unchanged exact swing
  calculation and interval check. An eight-bar phrase no longer requires scanning every
  event in three adjacent cycles during every 128-frame callback.
- Lazy FIR coefficient construction is explicitly warmed in engine prepare(), before
  audio starts. All voice, mix, event and meter storage is allocated before rendering.

## Existing constraints retained

File decoding, sample processing, kit construction, pattern generation and export stay
outside the audio callback. Audio-side queues, controls, kit handoffs and meters use
try-locks and retain the preceding state if a producer is busy. Callback event storage
is fixed at 512 events; normal loop data is sorted and normalized before publication.
The effects chain stops running after four seconds without sounding voices or transport.

Modern is the least expensive mode. Its INIT settings leave noise, punch, analog EQ,
grit and shine at zero. Vintage retains its built-in oversampled saturation, while
Texture retains downsampling, instability, delay and reverb. The master clipper also
uses oversampling when enabled. These effects have an audible purpose and were preserved.
NOISE is zero at INIT; turning it up intentionally introduces hiss and, in Vintage or
Texture, simulated vinyl crackle. Intentional crackle is distinct from a dropped buffer.

The app uses linear interpolation for pitched samples. The changes do not establish
perfect anti-aliasing at every extreme transposition, nor can they prevent route changes,
system interruptions, thermal throttling or external Bluetooth latency.

## Validation available here

`validation/test_schedule_bounds.py` passed eight Python numerical-model checks. It
compares the former exhaustive scheduler with the indexed scheduler over 5,000 random
intervals, all pads and swing extrema, exact boundaries, duplicate ticks, empty loops,
loop wraps, long-running song positions and split loop-change windows. This is a
mathematical bounds check, not execution of the production Swift engine.

For a representative 512-event eight-bar phrase in steady playback, the numerical
check examined at most four local candidate events instead of 1,536 exhaustive event
visits; each adjacent cycle additionally needs a binary search. These are operation
counts in one constructed case, not CPU benchmarks or percentages.

Swift grammar parsing passed for all 25 source files after these changes. Production
Swift self-test fixtures also check 128-versus-512-frame continuity across the three
modes and a forced voice-steal burst. They were authored but cannot execute without a
Swift compiler. Apple framework behavior, compilation and device timing remain pending.

## Device acceptance checks

1. Run on the target iPad with the intended wired or built-in audio route. Record
   AVAudioSession.sampleRate, ioBufferDuration and actual callback frame counts after
   activating the session; verify the route granted the requested 128 frames.
2. Run the longest, densest eight-bar loops, live pad hits and held/gliding 808 notes
   for at least ten minutes. Measure callback deadline misses and CPU with Apple's
   audio tools on the target device; repeat at the busiest effect settings actually used.
3. Switch kits during sustained bass and cymbal tails, change sample rate/routes,
   stop and resume, reverse imported samples, and generate dense MIDI bursts. Listen
   for discontinuities and verify there are no invalid sample-pointer accesses.
4. Repeat after the iPad is warm and with the normal companion apps running. A smaller
   buffer is a performance target; a static code review cannot certify that deadline.
