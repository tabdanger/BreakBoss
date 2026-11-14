// Stubs for the Linux table maker only: the Apple-only file writers the engine core links against.
import Foundation
enum WavWriter { static func write(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {} }
enum MIDIFile { static func write(_ source: PatternData, tempo: Double, bounce: Float, bars: Int, to url: URL) throws {} }
enum AudioFormats {
    static let extensions: Set<String> = ["wav", "caf", "aif", "aiff", "mp3", "m4a"]
    static func isAudio(_ url: URL) -> Bool { isAudio(ext: url.pathExtension) }
    static func isAudio(ext: String) -> Bool { extensions.contains(ext.lowercased()) }
}
struct mach_timebase_info_data_t { var numer: UInt32 = 1; var denom: UInt32 = 1 }
func mach_timebase_info(_ info: inout mach_timebase_info_data_t) {}
func mach_absolute_time() -> UInt64 { UInt64(Date().timeIntervalSince1970 * 1e9) }
extension URL {
    func startAccessingSecurityScopedResource() -> Bool { false }
    func stopAccessingSecurityScopedResource() {}
}
