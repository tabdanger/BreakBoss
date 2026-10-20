// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AudioToolbox
import AVFoundation
import XCTest

// MARK: - The AUv3 render block, driven the way a host drives it
//
// Built on GitHub (build.yml, "au_tests") into one bundle with the plug-in's own sources, so these
// call BreakBossAudioUnit's real internalRenderBlock with real AURenderEvent lists. Each timed
// result is compared with the same sound rendered in pieces with the change made at a piece's
// first sample (the engine renders split blocks sample for sample the same).

final class BreakBossAudioUnitTests: XCTestCase {
    static let rate = 48_000.0
    static let kit: KitBuffers = {
        let tone = SampleBuffer(left: (0..<24_000).map { sinf(Float($0) * 0.05) * 0.25 }, sampleRate: rate)
        return KitBuffers(name: "AU RENDER TEST", samples: Array(repeating: tone, count: Pad.count),
                          settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
    }()

    // MARK: Rig

    /// Host-side events for one callback, at offsets from its first sample.
    final class Events {
        private var list: [UnsafeMutablePointer<AURenderEvent>] = []

        func param(_ p: KParam, _ value: Float, at offset: Int, ramp: Int = 0) {
            var event = AUParameterEvent()
            event.eventType = ramp > 0 ? .parameterRamp : .parameter
            event.eventSampleTime = AUEventSampleTime(offset)
            event.rampDurationSampleFrames = AUAudioFrameCount(ramp)
            event.parameterAddress = AUParameterAddress(p.rawValue)
            event.value = value
            let e = UnsafeMutablePointer<AURenderEvent>.allocate(capacity: 1)
            e.initialize(to: AURenderEvent(parameter: event))
            list.append(e)
        }

        func midi(_ status: UInt8, _ d1: UInt8, _ d2: UInt8, at offset: Int) {
            var event = AUMIDIEvent()
            event.eventType = .MIDI
            event.eventSampleTime = AUEventSampleTime(offset)
            event.length = 3
            event.data = (status, d1, d2)
            let e = UnsafeMutablePointer<AURenderEvent>.allocate(capacity: 1)
            e.initialize(to: AURenderEvent(MIDI: event))
            list.append(e)
        }

        /// The linked list a host passes, with offsets turned into sample times from `start`.
        func head(start: AUEventSampleTime) -> UnsafePointer<AURenderEvent>? {
            for (i, e) in list.enumerated() {
                e.pointee.head.eventSampleTime += start
                e.pointee.head.next = i + 1 < list.count ? list[i + 1] : nil
            }
            return list.first.map { UnsafePointer($0) }
        }

        deinit { list.forEach { $0.deallocate() } }
    }

    /// One plug-in instance, as a host makes it, with a steady test kit and a running sample clock.
    final class Rig {
        let unit: BreakBossAudioUnit
        private(set) var clock: AUEventSampleTime = 10_000
        private let buffer: AVAudioPCMBuffer
        private let block: AUInternalRenderBlock

        init() throws {
            let description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
                                                         componentSubType: 0x6272_6273,       // brbs
                                                         componentManufacturer: 0x5464_6772,  // Tdgr
                                                         componentFlags: 0, componentFlagsMask: 0)
            unit = try BreakBossAudioUnit(componentDescription: description, options: [])
            try unit.allocateRenderResources()
            // The controller's own kit finishes loading first, so it can't replace the test kit.
            let deadline = Date().addingTimeInterval(30)
            while unit.controller.loadingKit && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            for (p, v): (KParam, Float) in [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.boost, 0),
                                            (.clipper, 0), (.clipDrive, 0), (.output, 1)] {
                unit.engine.setParam(p, v)
            }
            unit.engine.kitHandoff.publish(BreakBossAudioUnitTests.kit)
            buffer = AVAudioPCMBuffer(pcmFormat: unit.outputBusses[0].format, frameCapacity: 4_096)!
            block = unit.internalRenderBlock
            render(512)   // picks up the kit; the old one's voices fade out
        }

        /// One callback of `frames` samples; the left channel comes back.
        @discardableResult
        func render(_ frames: Int, _ events: Events? = nil) -> [Float] {
            buffer.frameLength = AVAudioFrameCount(frames)
            var flags = AudioUnitRenderActionFlags()
            var time = AudioTimeStamp()
            time.mSampleTime = Double(clock)
            time.mFlags = .sampleTimeValid
            let status = block(&flags, &time, AUAudioFrameCount(frames), 0, buffer.mutableAudioBufferList,
                                events?.head(start: clock), nil)
            XCTAssertEqual(status, noErr)
            clock += AUEventSampleTime(frames)
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: frames))
        }

        /// A kick held on (note 36), for automation to act on.
        func startTone() {
            let e = Events()
            e.midi(0x90, 36, 127, at: 0)
            render(128, e)
        }
    }

    func maxDifference(_ a: [Float], _ b: [Float]) -> Float {
        XCTAssertEqual(a.count, b.count)
        return zip(a, b).reduce(0) { max($0, abs($1.0 - $1.1)) }
    }

    func immediate(_ p: KParam, _ value: Float) -> Events {
        let e = Events()
        e.param(p, value, at: 0)
        return e
    }

    // MARK: Parameter events

    func testParameterEventIsHeardFromItsSampleOffset() throws {
        let timed = try Rig(), split = try Rig(), plain = try Rig()
        for rig in [timed, split, plain] { rig.startTone() }

        let e = Events()
        e.param(.output, 0.2, at: 64)
        let actual = timed.render(128, e)
        let expected = split.render(64) + split.render(64, immediate(.output, 0.2))
        let untouched = plain.render(128)

        XCTAssertLessThan(maxDifference(Array(actual.prefix(64)), Array(untouched.prefix(64))), 0.000_001,
                          "nothing changes before sample 64")
        XCTAssertGreaterThan(maxDifference(actual, untouched), 0.000_1, "the change is heard after sample 64")
        XCTAssertLessThan(maxDifference(actual, expected), 0.000_001, "same as changing it at sample 64")
        timed.render(128)
        XCTAssertEqual(timed.unit.engine.param(.output), 0.2, accuracy: 0.000_001, "the faceplate gets the value")
    }

    func testSeveralEventsInOneCallbackLandInOrder() throws {
        let timed = try Rig(), split = try Rig()
        for rig in [timed, split] { rig.startTone() }
        let e = Events()
        e.param(.output, 0.5, at: 17)
        e.param(.filter, 0.3, at: 17)
        e.param(.output, 0.1, at: 90)
        let actual = timed.render(128, e)
        let both = Events()
        both.param(.output, 0.5, at: 0)
        both.param(.filter, 0.3, at: 0)
        let expected = split.render(17) + split.render(73, both) + split.render(38, immediate(.output, 0.1))
        XCTAssertLessThan(maxDifference(actual, expected), 0.000_001)
    }

    func testOffsetPastTheCallbackCarriesToTheNext() throws {
        let timed = try Rig(), split = try Rig()
        for rig in [timed, split] { rig.startTone() }
        let e = Events()
        e.param(.output, 0.25, at: 160)
        let actual = timed.render(128, e) + timed.render(128)
        let expected = split.render(128) + split.render(32) + split.render(96, immediate(.output, 0.25))
        XCTAssertLessThan(maxDifference(actual, expected), 0.000_001)
    }

    // MARK: Ramps

    /// The value each ramp step is rendered at (KnockEngine.hostRampStep long, from the ramp's start).
    func rampSteps(from: Float, to: Float, length: Int) -> [(at: Int, value: Float)] {
        let step = KnockEngine.hostRampStep
        var steps = stride(from: 0, to: length, by: step).map { (at: $0, value: from + (to - from) * (Float($0) / Float(length))) }
        steps.append((at: length, value: to))
        return steps
    }

    func testRampCrossingBuffersMatchesItsSteps() throws {
        let timed = try Rig(), whole = try Rig(), stepped = try Rig()
        for rig in [timed, whole, stepped] { rig.startTone() }
        let from = timed.unit.engine.param(.output)
        let start = 40, length = 300

        func ramp() -> Events {
            let e = Events()
            e.param(.output, 0, at: start, ramp: length)
            return e
        }
        // three 128-sample callbacks, the ramp running through all of them
        let actual = timed.render(128, ramp()) + timed.render(128) + timed.render(128)
        // one 384-sample callback
        let single = whole.render(384, ramp())
        // the ramp's steps made by hand, each at its own first sample
        var expected = stepped.render(start)
        let steps = rampSteps(from: from, to: 0, length: length)
        for (i, s) in steps.enumerated() {
            let end = i + 1 < steps.count ? start + steps[i + 1].at : 384
            expected += stepped.render(end - (start + s.at), immediate(.output, s.value))
        }

        XCTAssertLessThan(maxDifference(actual, single), 0.000_001, "callback size doesn't change a ramp")
        XCTAssertLessThan(maxDifference(actual, expected), 0.000_001, "the ramp moves step by step from sample 40")
        XCTAssertLessThan(maxDifference(Array(actual.prefix(start)), Array(expected.prefix(start))), 0.000_001)
        timed.render(128)
        XCTAssertEqual(timed.unit.engine.param(.output), 0, accuracy: 0.000_001, "the ramp ends on its value")
    }

    func testRampIsShownWhileRunningAndANewValueEndsIt() throws {
        let rig = try Rig()
        rig.startTone()
        let e = Events()
        e.param(.output, 0, at: 0, ramp: 4_800)
        rig.render(128, e)
        rig.render(128)
        let shown = rig.unit.engine.param(.output)
        XCTAssertLessThan(shown, 1)
        XCTAssertGreaterThan(shown, 0.9, "the faceplate follows the ramp")
        rig.render(128, immediate(.output, 0.6))
        for _ in 0..<60 { rig.render(128) }
        XCTAssertEqual(rig.unit.engine.param(.output), 0.6, accuracy: 0.000_001, "a jump stops the ramp")
    }

    func testSteppedParameterRampsInWholeSteps() throws {
        let rig = try Rig()
        let e = Events()
        e.param(.soundMode, 2, at: 0, ramp: 256)
        rig.render(128, e)
        rig.render(128)
        let mid = rig.unit.engine.param(.soundMode)
        XCTAssertEqual(mid, mid.rounded())
        rig.render(128)
        rig.render(128)
        XCTAssertEqual(rig.unit.engine.param(.soundMode), 2)
    }

    // MARK: MIDI timing alongside automation

    func testMIDIKeepsItsOffsetAroundAutomation() throws {
        let timed = try Rig(), split = try Rig()
        let e = Events()
        e.param(.output, 0.5, at: 50)
        e.midi(0x90, 36, 127, at: 73)
        e.param(.output, 0.2, at: 90, ramp: 100)
        let actual = timed.render(256, e)
        XCTAssertTrue(actual.prefix(73).allSatisfy { abs($0) < 0.000_001 }, "silent before the note")
        XCTAssertTrue(actual.dropFirst(73).contains { abs($0) > 0.001 }, "the note starts on sample 73")

        var expected = split.render(50)
        let first = Events()
        first.param(.output, 0.5, at: 0)
        first.midi(0x90, 36, 127, at: 23)
        expected += split.render(40, first)
        for s in rampSteps(from: 0.5, to: 0.2, length: 100) where s.at < 100 {
            let end = min(s.at + KnockEngine.hostRampStep, 100)
            expected += split.render(end - s.at, immediate(.output, s.value))
        }
        expected += split.render(66, immediate(.output, 0.2))
        XCTAssertLessThan(maxDifference(actual, expected), 0.000_001)
    }

    func testHostScheduledParameterThroughRenderBlock() throws {
        let scheduled = try Rig(), listed = try Rig()
        for rig in [scheduled, listed] { rig.startTone() }
        // what a host does: schedule, then call the public render block
        scheduled.unit.scheduleParameterBlock(AUEventSampleTimeImmediate + 64, 0, AUParameterAddress(KParam.output.rawValue), 0.3)
        let buffer = AVAudioPCMBuffer(pcmFormat: scheduled.unit.outputBusses[0].format, frameCapacity: 128)!
        buffer.frameLength = 128
        var flags = AudioUnitRenderActionFlags()
        var time = AudioTimeStamp()
        time.mSampleTime = Double(scheduled.clock)
        time.mFlags = .sampleTimeValid
        XCTAssertEqual(scheduled.unit.renderBlock(&flags, &time, 128, 0, buffer.mutableAudioBufferList, nil), noErr)
        let actual = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 128))
        let e = Events()
        e.param(.output, 0.3, at: 64)
        XCTAssertLessThan(maxDifference(actual, listed.render(128, e)), 0.000_001)
    }

    // MARK: Concurrency

    func testAutomationSurvivesConcurrentControlUpdates() throws {
        let rig = try Rig()
        rig.startTone()
        let tree = try XCTUnwrap(rig.unit.parameterTree)
        let output = try XCTUnwrap(tree.parameter(withAddress: AUParameterAddress(KParam.output.rawValue)))
        let filter = try XCTUnwrap(tree.parameter(withAddress: AUParameterAddress(KParam.filter.rawValue)))
        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<5_000 {
                output.setValue(Float(i % 100) / 100, originator: nil)
                filter.value = Float(i % 7) / 7
                rig.unit.engine.setTempo(Double(80 + i % 80))
            }
            done.leave()
        }
        var finite = true
        for i in 0..<300 {
            let e = Events()
            e.param(.output, Float(i % 10) / 10, at: i % 128)
            if i % 3 == 0 { e.param(.filter, 0.5, at: 7, ramp: 200) }
            e.midi(0x90, 36, 100, at: (i * 37) % 128)
            finite = finite && rig.render(128, e).allSatisfy { $0.isFinite }
        }
        done.wait()
        let last = Events()
        last.param(.output, 0.33, at: 10)
        rig.render(128, last)
        rig.render(128)
        XCTAssertTrue(finite)
        XCTAssertEqual(rig.unit.engine.param(.output), 0.33, accuracy: 0.000_001, "the host's last value wins")
    }

    // MARK: MIDI out

    /// Counts what one MIDI output block receives; notes it if it's freed on the render thread.
    final class Receiver {
        static let lock = NSLock()
        static var freedOnRenderThread = 0
        static var delivered = 0
        private(set) var times: [AUEventSampleTime] = []
        private(set) var statuses: [UInt8] = []
        var count: Int { Receiver.lock.lock(); defer { Receiver.lock.unlock() }; return times.count }
        func block() -> AUMIDIOutputEventBlock {
            { [self] time, _, length, bytes in
                Receiver.lock.lock()
                times.append(time)
                if length > 0 { statuses.append(bytes[0]) }
                Receiver.delivered += 1
                Receiver.lock.unlock()
                return noErr
            }
        }
        deinit {
            if Thread.current.threadDictionary[BreakBossAudioUnitTests.renderMark] != nil {
                Receiver.lock.lock(); Receiver.freedOnRenderThread += 1; Receiver.lock.unlock()
            }
        }
        static func reset() { lock.lock(); freedOnRenderThread = 0; delivered = 0; lock.unlock() }
    }

    static let renderMark = "breakboss.render"

    /// Runs `work` on a thread of its own standing in for the host's render thread, and waits.
    func onRenderThread(_ work: @escaping () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        let thread = Thread {
            Thread.current.threadDictionary[BreakBossAudioUnitTests.renderMark] = true
            work()
            finished.signal()
        }
        thread.start()
        finished.wait()
    }

    /// A faceplate pad hit goes out as MIDI in the next callback.
    func hitPad(_ rig: Rig) { rig.unit.engine.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1)) }

    func testMIDIOutGoesToTheCurrentBlockAndFollowsReplacement() throws {
        let rig = try Rig()
        let a = Receiver(), b = Receiver()
        rig.unit.midiOutputEventBlock = a.block()
        hitPad(rig)
        let callStart = rig.clock
        rig.render(128)
        XCTAssertGreaterThan(a.count, 0, "MIDI out reaches the host's block")
        XCTAssertTrue(a.times.allSatisfy { $0 >= callStart && $0 < callStart + 128 }, "stamped inside the callback")
        XCTAssertTrue(a.statuses.contains { $0 & 0xF0 == 0x90 })

        rig.unit.midiOutputEventBlock = b.block()
        let before = a.count
        hitPad(rig)
        rig.render(128)
        XCTAssertEqual(a.count, before, "the replaced block gets nothing more")
        XCTAssertGreaterThan(b.count, 0, "the new block gets the next callback's MIDI")

        rig.unit.midiOutputEventBlock = nil
        let bBefore = b.count
        hitPad(rig)
        rig.render(128)
        XCTAssertEqual(b.count, bBefore, "routing removed: nothing goes out")
    }

    func testReplacedMIDIOutBlockIsReleasedOffTheRenderThread() throws {
        Receiver.reset()
        let rig = try Rig()
        weak var gone: Receiver?
        // (the AU's own property hands blocks through Objective-C, which may autorelease them)
        autoreleasepool {
            let first = Receiver()
            gone = first
            rig.unit.midiOutputEventBlock = first.block()
        }
        onRenderThread { for _ in 0..<4 { self.hitPad(rig); rig.render(128) } }
        XCTAssertNotNil(gone, "in use while it's the route")
        autoreleasepool { rig.unit.midiOutputEventBlock = Receiver().block() }
        onRenderThread { for _ in 0..<4 { self.hitPad(rig); rig.render(128) } }
        autoreleasepool { rig.unit.midiOutputEventBlock = nil }   // also releases what the render thread handed back
        XCTAssertNil(gone, "the replaced block is freed once routing changes again")
        XCTAssertEqual(Receiver.freedOnRenderThread, 0)
    }

    func testMIDIOutBlockSwappedWhileRendering() throws {
        Receiver.reset()
        let rig = try Rig()
        let stop = DispatchSemaphore(value: 0)
        final class Count { var value = 0 }
        let rendered = Count()
        let renderer = Thread {
            Thread.current.threadDictionary[BreakBossAudioUnitTests.renderMark] = true
            for _ in 0..<3_000 {
                rig.unit.engine.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1))
                rig.render(128)
                rendered.value += 1
            }
            stop.signal()
        }
        renderer.start()
        var swaps = 0
        while stop.wait(timeout: .now()) == .timedOut {
            // a new receiver every time: each replaced one is freed as soon as nothing holds it
            autoreleasepool { rig.unit.midiOutputEventBlock = swaps % 5 == 4 ? nil : Receiver().block() }
            swaps += 1
        }
        XCTAssertEqual(rendered.value, 3_000)
        XCTAssertGreaterThan(swaps, 10)
        XCTAssertGreaterThan(Receiver.delivered, 0)
        XCTAssertEqual(Receiver.freedOnRenderThread, 0, "no block is freed on the render thread")

        let last = Receiver()
        rig.unit.midiOutputEventBlock = last.block()
        hitPad(rig)
        rig.render(128)
        XCTAssertGreaterThan(last.count, 0, "after the swaps the newest block gets MIDI")
    }
}
