// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

/// A note the SAMPLER's arpeggiator or echo delay will play `due` samples from now.
struct PendingHit {
    var pad = 0
    var due = 0
    var velocity: Float = 0
    var semis: Float = 0
    var length = 0
    var pan: Float = 0, x: Float = 0, y: Float = 0
    var echo = false
    var slide = false
    /// An echo's level (FEED once per repeat), whatever the velocity setting.
    var level: Float = 1
    /// Chord "Auto (sustain)": this step of the track's arpeggio (its note is picked from the notes
    /// held when it plays); −1 = an ordinary hit.
    var arpStep = -1
}

// MARK: - A playing sound

struct Voice {
    var active = false
    var pad = 0
    var left: UnsafeMutablePointer<Float>?
    var right: UnsafeMutablePointer<Float>?
    var length = 0
    var position: Double = 0
    /// Where the note started in the sound (START OFFSET, or the end when it plays backwards).
    var startPosition: Double = 0
    var rate: Double = 1
    var targetRate: Double = 1
    var rateStep: Double = 0
    var glideLeft = 0
    var reverse = false
    var gainL: Float = 0
    var gainR: Float = 0
    var env: Float = 1
    var decayCoef: Float = 1
    var hold = 0
    var attack: Float = 1
    var attackStep: Float = 0
    var fade: Float = 1
    var fadeStep: Float = 0
    var releasing = false
    /// The note has ended and the sampler's Volume envelope is releasing it: a slide or glide starts a
    /// new note instead of bending this fading one (it used to bend it and the slid note faded out).
    var letGo = false
    var chokeGroup = 0
    var age: UInt32 = 0
    var remaining = Int.max
    var heldNote = -1
    var filterCoefficient: Float = 1
    var filterL: Float = 0
    var filterR: Float = 0
    /// The pad's LEVEL / PAN gains right now; render() glides them to the pad's current setting.
    var mixL: Float = 1
    var mixR: Float = 1
    /// The track's sampler (envelopes, LFOs, filter, loop), when it has one.
    var sm = SamplerVoice()

    init() {}

    init(sample: SampleBuffer, pad: Int, rate: Double, reverse: Bool, gainL: Float, gainR: Float,
         decayCoef: Float, holdSamples: Int, chokeGroup: Int, age: UInt32, remaining: Int, heldNote: Int,
         attackSamples: Int = 0, filterCoefficient: Float = 1, mixL: Float = 1, mixR: Float = 1) {
        active = true
        self.pad = pad
        left = sample.left
        right = sample.right
        length = sample.length
        self.rate = rate
        targetRate = rate
        self.reverse = reverse
        // backwards from the last frame it can read (length - 1 would end the voice before its first sample)
        position = reverse ? Double(max(0, sample.length - 2)) : 0
        startPosition = position
        self.gainL = gainL
        self.gainR = gainR
        self.decayCoef = decayCoef
        hold = holdSamples
        if attackSamples > 0 {
            attack = 0
            attackStep = 1 / Float(attackSamples)
        }
        self.chokeGroup = chokeGroup
        self.age = age
        self.remaining = remaining
        self.heldNote = heldNote
        self.filterCoefficient = filterCoefficient
        self.mixL = mixL
        self.mixR = mixR
    }

    mutating func startFade(samples: Int) {
        guard active else { return }
        releasing = true
        let step = 1 / Float(max(samples, 1))
        fadeStep = max(fadeStep, step)
        chokeGroup = -1   // a fading voice no longer belongs to a group
        heldNote = -1
    }

    mutating func release(samples: Int) { startFade(samples: samples) }

    /// The sampler takes over this voice: START OFFSET, loop points and the ENVELOPE page.
    mutating func startSampler(_ rt: SamplerRT, sampleRate: Double, samplesPerBeat: Double, clock: Int64, loopStart: Int,
                               loopEnd: Int, region: ClosedRange<Int>?, playRegion: Bool = false, offsets: (Float, Float, Float) = (0, 0, 0)) {
        sm = SamplerVoice(rt, sampleRate: sampleRate, samplesPerBeat: samplesPerBeat, clock: clock,
                          panOffset: offsets.0, xOffset: offsets.1, yOffset: offsets.2)
        let last = Double(max(length - 2, 0))
        let offset = Double(rt.startOffset) * last
        position = reverse ? last - offset : offset
        startPosition = position
        sm.looping = rt.loop && !reverse && length > 64
        sm.pingPong = rt.pingPong
        if loopEnd > 0 {
            // a CROSSFADE computed its loop into the sound
            sm.loopStart = min(Double(max(0, loopStart)), last * 0.95)
            sm.loopEnd = min(Double(loopEnd), last)
        } else {
            // the loop points (the whole sound unless they're set), after any crossfade start
            sm.loopStart = min(max(Double(max(0, loopStart)), Double(rt.loopStart) * last), last * 0.95)
            sm.loopEnd = max(sm.loopStart + 32, min(last, Double(rt.loopEnd) * last))
            if sm.loopEnd > last { sm.loopStart = max(0, last - 32); sm.loopEnd = last }
        }
        if let region, Double(region.upperBound) <= last, region.count > 32 {
            sm.loopStart = Double(region.lowerBound); sm.loopEnd = Double(region.upperBound)
            // a region drawn on the waveform: with no loop, the note plays just that part
            if playRegion && !sm.looping && !reverse {
                position = max(position, Double(region.lowerBound))
                startPosition = position
                sm.regionEnd = Double(region.upperBound)
            }
        }
    }

    /// Realtime stretching: `timeStep` is how fast the position moves through the sound (the length);
    /// the grains read it at the note's speed × `pitch`.
    mutating func startGrains(timeStep: Double, pitch: Double, sampleRate: Double) {
        sm.grains = true
        sm.timeStep = timeStep
        sm.grainPitch = pitch
        sm.grainHalf = max(64, Int(sampleRate * 0.035))
        sm.grainA = position; sm.grainB = position
        sm.grainAge = 0
    }

    /// The note's length is up: the sampler's envelopes release, or a loop plays out to its end.
    private mutating func noteEnded(releaseSamples: Int) {
        guard sm.on else { release(samples: releaseSamples); return }
        // GATE: with no Volume envelope to release, the sound stops at the gate
        if sm.gateCut && !sm.volumeGates { release(samples: releaseSamples); return }
        // no Volume envelope release and no loop: the note ends as it would with no sampler
        if !sm.volumeGates && !sm.looping { release(samples: releaseSamples); return }
        sm.release()
        if sm.volumeGates { letGo = true }
        // with the Volume envelope the loop keeps going under its release; without it the sound plays out
        if !sm.volumeGates && sm.looping { sm.looping = false; sm.direction = 1 }
    }

    mutating func glide(to newRate: Double, samples: Int) {
        targetRate = newRate
        glideLeft = max(samples, 1)
        rateStep = (newRate - rate) / Double(glideLeft)
    }

    @inline(__always)
    mutating func render(into outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, releaseSamples: Int,
                         targetL: Float = 1, targetR: Float = 1, mixStep: Float = 1) {
        guard let left, let right else { active = false; return }
        if sm.on {
            renderSampler(left, right, into: outL, outR, frames: frames, releaseSamples: releaseSamples,
                          targetL: targetL, targetR: targetR, mixStep: mixStep)
            return
        }
        let last = Double(length - 1)
        for i in 0..<frames {
            if remaining != Int.max {
                remaining -= 1
                if remaining == 0 { release(samples: releaseSamples); remaining = Int.max }
            }
            if position < 0 || position >= last { active = false; return }
            let idx = Int(position)
            let frac = Float(position - Double(idx))
            var l = left[idx] + (left[idx + 1] - left[idx]) * frac
            var r = right[idx] + (right[idx + 1] - right[idx]) * frac
            if filterCoefficient < 1 {
                filterL += filterCoefficient * (l - filterL)
                filterR += filterCoefficient * (r - filterR)
                l = filterL
                r = filterR
            }
            var g = env * fade
            if hold > 0 { hold -= 1 } else { env *= decayCoef }
            if releasing {
                fade -= fadeStep
                if fade <= 0 { active = false; return }
                g = env * fade
            }
            if attack < 1 {
                g *= attack
                attack = min(1, attack + attackStep)
            }
            if g < 0.000_05 && env < 0.000_05 { active = false; return }
            if mixL != targetL { mixL = targetL > mixL ? min(targetL, mixL + mixStep) : max(targetL, mixL - mixStep) }
            if mixR != targetR { mixR = targetR > mixR ? min(targetR, mixR + mixStep) : max(targetR, mixR - mixStep) }
            outL[i] += l * g * gainL * mixL
            outR[i] += r * g * gainR * mixR
            if glideLeft > 0 {
                rate += rateStep
                glideLeft -= 1
                if glideLeft == 0 { rate = targetRate }
            }
            position += reverse ? -rate : rate
        }
    }
    /// render() for a voice with a sampler: the envelopes, LFOs and filter are worked out every 16
    /// samples (the volume glides between them so nothing steps), the loop wraps or ping-pongs.
    @inline(__always)
    private mutating func renderSampler(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>,
                                        into outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int,
                                        releaseSamples: Int, targetL: Float, targetR: Float, mixStep: Float) {
        let last = Double(length - 1)
        var i = 0
        while i < frames {
            let n = min(16, frames - i)
            let g0 = sm.gain
            sm.control(n)
            if sm.done { active = false; return }
            let gStep = (sm.gain - g0) / Float(n)
            var gs = g0
            for j in i..<(i + n) {
                if remaining != Int.max {
                    remaining -= 1
                    if remaining == 0 { noteEnded(releaseSamples: releaseSamples); remaining = Int.max }
                }
                if sm.looping {
                    if sm.direction > 0 && position >= sm.loopEnd {
                        if sm.pingPong { sm.direction = -1; position = max(sm.loopStart, 2 * sm.loopEnd - position) }
                        else { position = max(sm.loopStart, position - (sm.loopEnd - sm.loopStart)) }
                    } else if sm.direction < 0 && position <= sm.loopStart {
                        sm.direction = 1; position = min(sm.loopEnd, 2 * sm.loopStart - position)
                    }
                }
                if position < 0 || position >= last { active = false; return }
                if sm.regionEnd > 0 && position >= sm.regionEnd - 240 * rate { startFade(samples: 240); sm.regionEnd = 0 }
                var l: Float, r: Float
                if sm.grains {
                    // two grains, half a grain apart: the newest fades in as the one before fades out
                    if sm.grainAge >= sm.grainHalf { sm.grainB = sm.grainA; sm.grainA = position; sm.grainAge = 0 }
                    let step = rate * sm.rateMul * sm.grainPitch
                    let w = 0.5 - 0.5 * cosf(.pi * Float(sm.grainAge) / Float(sm.grainHalf))
                    let pa = sm.grainA + Double(sm.grainAge) * step
                    let pb = sm.grainB + Double(sm.grainAge + sm.grainHalf) * step
                    var la: Float = 0, ra: Float = 0, lb: Float = 0, rb: Float = 0
                    if pa >= 0 && pa < last {
                        let k = Int(pa), t = Float(pa - Double(k))
                        la = left[k] + (left[k + 1] - left[k]) * t; ra = right[k] + (right[k + 1] - right[k]) * t
                    }
                    if pb >= 0 && pb < last {
                        let k = Int(pb), t = Float(pb - Double(k))
                        lb = left[k] + (left[k + 1] - left[k]) * t; rb = right[k] + (right[k + 1] - right[k]) * t
                    }
                    l = la * w + lb * (1 - w)
                    r = ra * w + rb * (1 - w)
                    sm.grainAge += 1
                } else {
                    let idx = Int(position)
                    let frac = Float(position - Double(idx))
                    l = left[idx] + (left[idx + 1] - left[idx]) * frac
                    r = right[idx] + (right[idx + 1] - right[idx]) * frac
                }
                sm.filter(&l, &r)
                if filterCoefficient < 1 {
                    filterL += filterCoefficient * (l - filterL)
                    filterR += filterCoefficient * (r - filterR)
                    l = filterL
                    r = filterR
                }
                gs += gStep
                var g = env * fade
                if hold > 0 { hold -= 1 } else { env *= decayCoef }
                if releasing {
                    fade -= fadeStep
                    if fade <= 0 { active = false; return }
                    g = env * fade
                }
                if attack < 1 {
                    g *= attack
                    attack = min(1, attack + attackStep)
                }
                if env < 0.000_05 { active = false; return }
                if mixL != targetL { mixL = targetL > mixL ? min(targetL, mixL + mixStep) : max(targetL, mixL - mixStep) }
                if mixR != targetR { mixR = targetR > mixR ? min(targetR, mixR + mixStep) : max(targetR, mixR - mixStep) }
                g *= gs
                outL[j] += l * g * gainL * mixL * sm.panL
                outR[j] += r * g * gainR * mixR * sm.panR
                if glideLeft > 0 {
                    rate += rateStep
                    glideLeft -= 1
                    if glideLeft == 0 { rate = targetRate }
                }
                if sm.grains { position += sm.timeStep * sm.direction }
                else { position += (reverse ? -rate : rate) * sm.rateMul * sm.direction }
            }
            i += n
        }
    }
}
