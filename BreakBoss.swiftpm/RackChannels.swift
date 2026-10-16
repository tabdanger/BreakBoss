// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

/// The channel rack holds up to twelve independent sounds, matching the performance pads.
enum RackLimits {
    static let maxChannels = 12
    /// Additional rows share this decoded stereo-PCM budget; legacy pad audio is preserved.
    static let extraDecodedByteLimit = 64 * 1024 * 1024
}

/// A row keeps its audio slot when it moves, so existing notes never change instruments.
/// Sample URLs are deliberately not saved: imported audio lives relative to Samples/.
struct RackChannel: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var slot: Int
    var name: String? = nil
    var role: Int
    var libraryID: String? = nil
    var stockFileName: String? = nil
    /// The recorded fundamental for factory bass samples, independent of the selected kit.
    var sourceBassHz: Float? = nil
    /// nil supports early project files; the original twelve rows follow the kit by default.
    var followsKit: Bool? = nil

    var usesKitSound: Bool { followsKit ?? (slot < Pad.count) }

    static func legacyID(slot: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", slot + 1))!
    }

    static var legacy: [RackChannel] {
        (0..<Pad.count).map { RackChannel(id: legacyID(slot: $0), slot: $0, role: $0, followsKit: true) }
    }

    static func normalized(_ source: [RackChannel]?) -> [RackChannel] {
        guard let source else { return legacy }
        var slots = Set<Int>()
        var identities = Set<UUID>()
        return source.prefix(RackLimits.maxChannels).compactMap { channel in
            guard (0..<RackLimits.maxChannels).contains(channel.slot), slots.insert(channel.slot).inserted else { return nil }
            var channel = channel
            if !identities.insert(channel.id).inserted {
                channel.id = legacyID(slot: channel.slot)
                while !identities.insert(channel.id).inserted { channel.id = UUID() }
            }
            channel.role = channel.role.clamped(0, Pad.count - 1)
            if let hz = channel.sourceBassHz, !hz.isFinite || hz <= 0 { channel.sourceBassHz = nil }
            channel.name = channel.name.map { String($0.prefix(120)) }
            if let file = channel.stockFileName,
               file.hasPrefix("/") || file.split(separator: "/").contains("..") {
                channel.stockFileName = nil
            }
            return channel
        }
    }

    static func availableSlot(in channels: [RackChannel]) -> Int? {
        let used = Set(channels.map(\.slot))
        return (0..<RackLimits.maxChannels).first { !used.contains($0) }
    }

    static func role(for type: SoundType) -> Int {
        switch type {
        case .kick: return 0
        case .snare: return 1
        case .clap: return 2
        case .rim: return 3
        case .hat: return 4
        case .open: return 5
        case .bass: return 6
        case .perc, .fx: return 7
        case .tom: return 9
        case .cymbal: return 11
        }
    }
}

/// Control-plane reservations cover concurrent drop requests before their UI commits.
/// No method is called from the audio callback. Replacing a row reserves its resulting size.
final class RackDecodedBudget {
    private let lock = NSLock()
    private let limit: Int
    private var committed: [UUID: Int] = [:]
    private var pending: [UUID: (channel: UUID, bytes: Int)] = [:]

    init(limit: Int = RackLimits.extraDecodedByteLimit) { self.limit = max(0, limit) }

    private func costs(excluding request: UUID? = nil) -> [UUID: Int] {
        var costs = committed
        for (key, reservation) in pending where key != request {
            costs[reservation.channel] = max(costs[reservation.channel] ?? 0, reservation.bytes)
        }
        return costs
    }

    @discardableResult
    func reserve(request: UUID, channel: UUID, bytes: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard bytes >= 0, bytes <= limit else { return false }
        var values = costs(excluding: request)
        values[channel] = max(values[channel] ?? 0, bytes)
        guard values.values.reduce(0, +) <= limit else { return false }
        pending[request] = (channel, bytes)
        return true
    }

    func cancel(_ request: UUID) {
        lock.lock(); defer { lock.unlock() }
        pending[request] = nil
    }

    func synchronize(_ current: [UUID: Int]) {
        lock.lock(); defer { lock.unlock() }
        committed = current
    }

    var reservedBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return costs().values.reduce(0, +)
    }
}

/// Superseded kit work exits between decodes instead of building a queue of discarded kits.
final class RackBuildCancellation {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
