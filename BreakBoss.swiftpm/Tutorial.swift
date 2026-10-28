// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The tutorial (Tyrone, Oct 20)
//
// A step-by-step tour of every part of BreaKing, skippable at any step. Each step lights one part of
// the real faceplate (Face 1) or the Drum Sequencer (Face 2) and dims the rest; the lit part still
// plays, so you can try it. The card that explains it is a plate of the face's own metal with a dark
// window and real pressing keys. It opens by itself on the app's first launch, and again from
// MENU › Tutorial. Nothing here touches the audio.

final class TutorialGuide: ObservableObject {
    static let shared = TutorialGuide()
    static let seenKey = "breakboss.tutorialSeen"

    /// The step on screen; nil while the tutorial is off.
    @Published private(set) var index: Int?

    func start() { withAnimation(.easeInOut(duration: 0.25)) { index = 0 } }

    func next() {
        guard let i = index else { return }
        if i + 1 < TutorialStep.all.count {
            withAnimation(.easeInOut(duration: 0.25)) { index = i + 1 }
        } else {
            finish()
        }
    }

    func back() {
        guard let i = index, i > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) { index = i - 1 }
    }

    /// SKIP or DONE: it closes and doesn't open by itself again (MENU › Tutorial plays it again).
    func finish() {
        withAnimation(.easeOut(duration: 0.2)) { index = nil }
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }

    /// The app's first launch. Never on the build machine's test runs (they set BREAKBOSS_ variables).
    func startIfFirstLaunch() {
        let env = ProcessInfo.processInfo.environment
        guard index == nil, !UserDefaults.standard.bool(forKey: Self.seenKey),
              !env.keys.contains(where: { $0.hasPrefix("BREAKBOSS_") }) else { return }
        start()
    }
}

// MARK: - The steps

struct TutorialStep {
    enum Surface { case face1, face2 }

    let surface: Surface
    let title: String
    let text: String
    /// What the step lights on Face 1, in the face's own art pixels (each face has its own layout).
    var face1: (FaceplateLayout) -> [[Double]] = { _ in [] }
    /// What the step lights on Face 2, in SequencerView.A's art pixels. The first one places the card.
    var face2: [[Double]] = []

    static func union(_ rects: [[Double]]) -> [Double] {
        guard let first = rects.first else { return [0, 0, 0, 0] }
        return rects.dropFirst().reduce(first) { [min($0[0], $1[0]), min($0[1], $1[1]), max($0[2], $1[2]), max($0[3], $1[3])] }
    }

    private typealias A = SequencerView.A

    static let all: [TutorialStep] = [
        // Face 1
        TutorialStep(surface: .face1, title: "THE TOUR",
                     text: "BreaKing is a drum machine you play with your fingers, a 12-track drum sequencer and a plug-in for your DAW. This tour lights up each part, one step at a time. SKIP ends it at any step; MENU › Tutorial plays it again."),
        TutorialStep(surface: .face1, title: "THE MODES",
                     text: "Each mode is its own faceplate and its own sound. MODERN is clean and punchy. VINTAGE has tape drive, warm lows and a rolled-off top. TEXTURE adds resampling, instability, synced delay and a plate reverb, each only as you turn its knob up. PLATINUM is Modern's brushed-silver face (MENU › Modern faceplate). Every kit plays in every mode.",
                     face1: { L in [TutorialStep.union(Array(L.modeButtons.values))] }),
        TutorialStep(surface: .face1, title: "ONE-SHOT / LOOP",
                     text: "ONE-SHOT: each pad plays one drum. LOOP: each pad starts a groove made from the kit, locked to the tempo. A new pick starts on the next bar; tap the same pad again to stop it at the end of the bar.",
                     face1: { L in [TutorialStep.union([L.oneShotButton, L.loopButton])] }),
        TutorialStep(surface: .face1, title: "THE PADS",
                     text: "12 pads, one sound each, made for finger drumming. Go on, play them: they work during the tour. Hold a pad for its editor (level, pan, tune, decay, filter, reverse, your own sample), or drop an audio file on a pad to load it.",
                     face1: { L in [TutorialStep.union(L.pads)] }),
        TutorialStep(surface: .face1, title: "RECORD LIVE INTO YOUR DAW",
                     text: "Everything you play goes out as MIDI. In your DAW, load BreaKing as an AUv3 instrument (or turn on MIDI out in MENU for the app), record its MIDI onto a track and your playing lands in the piano roll: each pad on its own channel 1–12, notes 36–47. Pad controllers play the pads too (MENU › MIDI controller).",
                     face1: { L in [TutorialStep.union(L.pads)] }),
        TutorialStep(surface: .face1, title: "RECORD INTO THE PATTERN",
                     text: "RECORD counts in (1 or 2 bars, set in MENU › Record), then the pattern plays and every pad you hit lands in it on that pad's own track. Open the sequencer to edit what you played.",
                     face1: { L in L.recordRect.map { [$0] } ?? [] }),
        TutorialStep(surface: .face1, title: "KITS AND PRESETS",
                     text: "KITS change the drum sounds only; the pattern keeps playing. PRESETS change the pattern only: groove, variation and tempo. Mix any preset with any kit. SAVE keeps the whole faceplate as your own preset.",
                     face1: { L in [L.kitBox, L.presetBox, L.saveRect] }),
        TutorialStep(surface: .face1, title: "THE MAIN FX KNOBS",
                     text: "These knobs shape the whole mix. The top two rows set pitch, tune, bounce (swing), velocity, filter, the clipper's drive and the output; the CLIPPER button switches it on and off. The long row colours the sound in the mode's own style. Drag up or right to turn a knob up; double-tap to reset it.",
                     face1: { L in [TutorialStep.union(L.knobs.values.map { [$0.x - $0.r, $0.y - $0.r, $0.x + $0.r, $0.y + $0.r] } + [L.clipperRect])] }),
        TutorialStep(surface: .face1, title: "THE DICE",
                     text: "The faceplate dice rolls new sounds onto the kit's pads (your own samples stay put). BreaKing has four dice with four jobs; you'll meet the other three in the sequencer.",
                     face1: { L in [L.diceRect] }),
        TutorialStep(surface: .face1, title: "PLAY AND TEMPO",
                     text: "PLAY starts and stops. Drag the BPM display up or down; double-tap it for the kit's tempo. TEMPO SYNC follows your DAW's or a MIDI clock's tempo, and FOLLOW DAW starts and stops with its transport.",
                     face1: { L in [TutorialStep.union([L.playRect, L.bpmBox, L.leds.tempoSyncRect, L.leds.followDAWRect])] }),
        TutorialStep(surface: .face1, title: "EXPORT AND MENU",
                     text: "EXPORT renders MIDI, a stereo mix and stems to drag into a DAW or share. MENU holds MIDI out, your pad controller's mapping, your samples and kits, the bug report and this tutorial.",
                     face1: { L in [TutorialStep.union([L.exportRect, L.menuRect])] }),
        TutorialStep(surface: .face1, title: "OPEN THE SEQUENCER",
                     text: "The piano-keys button, or sliding the round key at the bottom left, opens the Drum Sequencer. Press NEXT and it opens for you.",
                     face1: { L in (L.editorRect.map { [$0] } ?? []) + [L.sliderRect ?? [125, 1004, 235, 1040]] }),
        // Face 2
        TutorialStep(surface: .face2, title: "THE DRUM SEQUENCER",
                     text: "Each row is a track, one for each pad. DRAW: tap a step to add a note, tap a note to delete it, drag along a row to paint. SELECT boxes notes to move, DUPLICATE or CLEAR them; ERASE wipes over them. UNDO and REDO sit next to the tools.",
                     face2: [[A.gridX0, A.labelsY - 14, A.gridX1, A.rowsY1], TutorialStep.union(A.tools + [A.undo, A.redo])]),
        TutorialStep(surface: .face2, title: "REPEATED NOTES",
                     text: "Hold a step and pull down: the further you pull, the more even hits share that step, for rolls and hi-hat runs. A light in the step's slot shows each hit. Ease back up for fewer.",
                     face2: [[A.gridX0, A.rowsY0, A.gridX1, A.rowsY0 + A.rowH * 2]]),
        TutorialStep(surface: .face2, title: "PITCH AND SNAP TO SCALE",
                     text: "Tap a track's ▶ tab to drop down its lane, then PITCH to open its piano roll and move notes up and down. KEY, SCALE and SNAP in the roll (or the tuning fork on the SNAP chip) keep every note in the scale. The SNAP chip sets the grid: beats, steps, triplets or free.",
                     face2: [A.snap, [A.rackX0, A.rowsY0, A.rackX0 + 33, A.rowsY1]]),
        TutorialStep(surface: .face2, title: "VELOCITY",
                     text: "The same ▶ tab opens the VELOCITY lane under the track: drag the bars to set how hard each note hits. OFFSET nudges notes early or late, and CHANCE lets a note play only some of the time. The lane's dice rolls new velocities.",
                     face2: [[A.rackX0, A.rowsY0, A.rackX1, A.rowsY1]]),
        TutorialStep(surface: .face2, title: "SWING AND HUMANIZE",
                     text: "SWING pushes every other step late for a shuffle. HUMANIZE plays the pattern like a live drummer: accents, pocket, ghost notes and small timing moves. Turn the knob on each chip, or tap the chip for its slider.",
                     face2: [TutorialStep.union([A.swing, A.humanize])]),
        TutorialStep(surface: .face2, title: "PATTERNS AND KITS",
                     text: "Step through patterns and kits with the arrows, or tap a chip for the whole list. PATTERN changes only the notes and KIT only the sounds, so any pattern plays with any kit, even while it runs.",
                     face2: [TutorialStep.union([A.patternBack, A.patternChip]), TutorialStep.union([A.kitBack, A.kitChip])]),
        TutorialStep(surface: .face2, title: "FOUR DICE, FOUR JOBS",
                     text: "The dice beside each track: new steps for that track only (✕ clears it). The dice in a track's VELOCITY lane: new velocities. GENERATE on the left: a new pattern in the genre you pick, with new sounds on every track when UPDATE SOUNDS is on. The faceplate dice: new sounds.",
                     face2: [[A.gridX1 + 4, A.rowsY0, A.panelX1, A.rowsY1], A.leftPanel]),
        TutorialStep(surface: .face2, title: "FX FOR EACH TRACK",
                     text: "These knobs are the FX of the track picked on the rack: every track, and its pad, has its own. Tap a track to pick it; the readout names the track as you turn. They change with the mode, and Face 1's knobs stay the main mix. Right-click a track's name for its menu: its settings and MIDI, the sample editor, SOLO, load or clear a sample.",
                     face2: [[A.fxX0, A.fxLabelY0, A.fxX1, A.fxKnobY1 + 4], [A.rackX0, A.rowsY0, A.rackX1, A.rowsY1]]),
        TutorialStep(surface: .face2, title: "THE SAMPLER EDITOR",
                     text: "Every track has its own SAMPLER, a window that edits that track's sound and its pad's. Right-click a track's name and pick Open Sample Editor. Drag its title bar to move it, minimize it to a tab in the corner, and drop an audio file on it to load your own sample. UNDO and REDO take back any change.",
                     face2: [[A.rackX0, A.rowsY0, A.rackX1, A.rowsY1]]),
        TutorialStep(surface: .face2, title: "SAMPLER: SAMPLE PAGE",
                     text: "The waveform: tap it to hear the sound, drag to select part of it, then CUT, COPY, PASTE, TRIM or FADE it. Drag the Start flag to start later in the sound, and the loop flags to loop it. The knobs set its volume (up to 200% here only), pan and pitch, plus its own EQ, boost, ring mod, delay and reverb."),
        TutorialStep(surface: .face2, title: "SAMPLER: ENVELOPE PAGE",
                     text: "Shape the sound over time. Pick what the envelope moves (volume, panning, pitch, MOD X or MOD Y) and set DELAY, ATTACK, HOLD, DECAY, SUSTAIN and RELEASE, or drag its points. Bring SUS down or REL up to shorten a hit; every sound plays out in full until you do. The LFO wobbles it, and the Filter's MOD X and MOD Y are its cutoff and resonance."),
        TutorialStep(surface: .face2, title: "SAMPLER: MISC PAGE",
                     text: "The rest of the track: how velocity and key change its volume, pan and filter, how many hits ring at once and SLIDE between them, GATE, SHIFT (push or pull the track in time) and the track's own SWING, CUT and BY (one sound chokes another, like a closed hat cutting an open one), echoes and chords. The tabs at the top switch pages."),
        TutorialStep(surface: .face2, title: "PLAY, RECORD, TEMPO",
                     text: "PLAY and STOP, and RECORD: it writes what you play on the pads or a MIDI controller into the pattern. Drag BPM to change the tempo; BARS sets the pattern's length. TEMPO SYNC and FOLLOW DAW lock it to your DAW. The space bar plays and stops.",
                     face2: [TutorialStep.union([A.stop, A.bars, A.tempoSync, A.followDAW])]),
        // Face 1
        TutorialStep(surface: .face1, title: "YOU'RE READY",
                     text: "That's BreaKing: the modes, the pads, the sequencer and the FX. Slide the round key at the bottom of either face to switch between them. MENU › Tutorial plays this tour again any time.")
    ]
}

// MARK: - The overlay: the dimmed face, the lit part, and the card

/// Sits on top of a face's art, in its own pixels × `scale`. On Face 1 it also carries the card for a
/// Face 2 step when the sequencer has been closed, so NEXT and BACK are always in reach.
struct TutorialOverlay: View {
    let surface: TutorialStep.Surface
    /// The face's art size in its own pixels, and the scale it's drawn at.
    let art: CGSize
    let scale: CGFloat
    let finish: String
    let spots: (TutorialStep) -> [[Double]]
    @ObservedObject private var guide = TutorialGuide.shared

    static let cardW: Double = 560
    /// About how tall the card comes out (art px), to find room for it beside the lit part.
    static let cardH: Double = 300

    var body: some View {
        if let i = guide.index, TutorialStep.all.indices.contains(i) {
            let step = TutorialStep.all[i]
            if step.surface == surface || surface == .face1 {
                content(step, index: i, spots: step.surface == surface ? spots(step) : [])
                    .transition(.opacity)
            }
        }
    }

    /// The lit colour of each face (as on Face 2: red on Modern and Platinum, amber on Vintage, blue on Texture).
    private var accent: Color {
        switch finish {
        case "vintage": return Color(red: 1, green: 0.74, blue: 0.2)
        case "texture": return Color(red: 0.25, green: 0.6, blue: 1)
        default: return Color(red: 1, green: 0.2, blue: 0.16)
        }
    }

    private func content(_ step: TutorialStep, index: Int, spots: [[Double]]) -> some View {
        let s = scale
        let holes = spots.map { CGRect(x: ($0[0] - 8) * s, y: ($0[1] - 8) * s, width: ($0[2] - $0[0] + 16) * s, height: ($0[3] - $0[1] + 16) * s) }
        let corner = 12 * s
        let p = place(spots)
        return ZStack(alignment: .topLeading) {
            // the rest of the face dimmed and still; the lit part keeps playing
            TutorialScrim(holes: holes, corner: corner)
                .fill(Color.black.opacity(0.64), style: FillStyle(eoFill: true))
                .contentShape(TutorialScrim(holes: holes, corner: corner), eoFill: true)
                .onTapGesture {}
            ForEach(holes.indices, id: \.self) { k in
                RoundedRectangle(cornerRadius: corner)
                    .stroke(accent, lineWidth: 2.5 * s)
                    .shadow(color: accent.opacity(0.9), radius: 8 * s)
                    .frame(width: holes[k].width, height: holes[k].height)
                    .offset(x: holes[k].minX, y: holes[k].minY)
                    .allowsHitTesting(false)
            }
            card(step, index: index)
                .frame(width: Self.cardW * s)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, p.x * s)
                .padding(p.fromBottom ? .bottom : .top, p.y * s)
                .frame(width: art.width * s, height: art.height * s, alignment: p.fromBottom ? .bottomLeading : .topLeading)
        }
        .frame(width: art.width * s, height: art.height * s, alignment: .topLeading)
    }

    private struct Place { var x: Double; var y: Double; var fromBottom: Bool }

    /// Where the card goes (art px): under the lit part, else over it, else beside it.
    private func place(_ spots: [[Double]]) -> Place {
        let W = Double(art.width), H = Double(art.height), m = 24.0, cw = Self.cardW, ch = Self.cardH
        func clampX(_ x: Double) -> Double { min(max(x, m), W - cw - m) }
        func clampY(_ y: Double) -> Double { min(max(y, m), H - ch - m) }
        guard let r = spots.first else { return Place(x: (W - cw) / 2, y: (H - ch) / 2, fromBottom: false) }
        let midX = (r[0] + r[2]) / 2, midY = (r[1] + r[3]) / 2
        if H - r[3] - 2 * m >= ch { return Place(x: clampX(midX - cw / 2), y: r[3] + m, fromBottom: false) }
        if r[1] - 2 * m >= ch { return Place(x: clampX(midX - cw / 2), y: H - r[1] + m, fromBottom: true) }
        if W - r[2] - 2 * m >= cw { return Place(x: r[2] + m, y: clampY(midY - ch / 2), fromBottom: false) }
        if r[0] - 2 * m >= cw { return Place(x: r[0] - m - cw, y: clampY(midY - ch / 2), fromBottom: false) }
        return Place(x: clampX(midX - cw / 2), y: m, fromBottom: true)
    }

    /// A plate of the face's metal: a dark window with the words lit in it, and the keys under it.
    private func card(_ step: TutorialStep, index: Int) -> some View {
        let s = scale
        let tone = MetalTone.of(finish)
        let count = TutorialStep.all.count
        let last = index == count - 1
        return VStack(alignment: .leading, spacing: 14 * s) {
            VStack(alignment: .leading, spacing: 9 * s) {
                HStack(spacing: 8 * s) {
                    Text(step.title).font(.system(size: 20 * s, weight: .bold, design: .monospaced)).foregroundColor(accent)
                        .shadow(color: accent.opacity(0.6), radius: 3 * s)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4 * s)
                    Text("\(index + 1) / \(count)").font(.system(size: 13 * s, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                }
                Text(step.text).font(.system(size: 17 * s)).foregroundColor(Color(white: 0.92))
                    .fixedSize(horizontal: false, vertical: true)
                // a lamp for each step, lit up to this one
                HStack(spacing: 4 * s) {
                    ForEach(0..<count, id: \.self) { k in
                        Circle().fill(k <= index ? accent : Color(white: 0.2))
                            .shadow(color: k == index ? accent : .clear, radius: 3 * s)
                            .frame(width: 7 * s, height: 7 * s)
                    }
                }
            }
            .padding(14 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8 * s)
                .fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 8 * s)
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.85), tone.bright.opacity(0.75)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * s))
            HStack(spacing: 10 * s) {
                if !last { TutorialKey(title: "SKIP", scale: s, id: "tutorialSkip") { guide.finish() } }
                Spacer(minLength: 0)
                if index > 0 { TutorialKey(title: "BACK", scale: s, id: "tutorialBack") { guide.back() } }
                TutorialKey(title: last ? "DONE" : "NEXT", lit: accent, scale: s, id: "tutorialNext") { guide.next() }
            }
        }
        .padding(16 * s)
        .background(PlatinumPlate(corner: 14 * s))
        .shadow(color: .black.opacity(0.6), radius: 14 * s, y: 6 * s)
        .environment(\.seqFinish, finish)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tutorialCard")
    }
}

/// The dimmed face with a hole over each lit part (even-odd, so the holes stay clear and touchable).
private struct TutorialScrim: Shape {
    let holes: [CGRect]
    let corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        for h in holes { p.addRoundedRect(in: h, cornerSize: CGSize(width: corner, height: corner)) }
        return p
    }
}

/// A dark key on the plate, like Face 2's transport keys: it goes in and springs back; NEXT is lit.
private struct TutorialKey: View {
    let title: String
    var lit: Color? = nil
    var scale: CGFloat = 1
    var id = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(lit ?? Color(white: 0.88))
                .shadow(color: (lit ?? .clear).opacity(0.8), radius: 3 * scale)
                .frame(width: 108 * scale, height: 48 * scale)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8 * scale)
                            .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                        BrushedFinish(corner: 8 * scale)
                        if let lit {
                            RoundedRectangle(cornerRadius: 8 * scale).stroke(lit, lineWidth: 1.5 * scale)
                                .shadow(color: lit.opacity(0.7), radius: 4 * scale)
                        }
                    }
                )
                .shadow(color: .black.opacity(0.5), radius: 2 * scale, y: 2 * scale)
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier(id)
    }
}
