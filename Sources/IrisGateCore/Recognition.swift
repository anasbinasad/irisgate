import Foundation

public enum Embeddings {
    public static func normalize(_ values: [Float]) -> [Float]? {
        guard !values.isEmpty, values.allSatisfy({ $0.isFinite }) else { return nil }
        let norm = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0.000001 else { return nil }
        return values.map { $0 / norm }
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, let a = normalize(a), let b = normalize(b) else { return nil }
        return min(1, max(-1, zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }))
    }
}

public struct Enrollment: Codable {
    public let version: Int
    public let modelDigest: String
    public let samples: [[Float]]
    public let createdAt: Date

    public init(modelDigest: String, samples: [[Float]]) {
        self.version = 1
        self.modelDigest = modelDigest
        self.samples = samples
        self.createdAt = Date()
    }

    public func similarity(to vector: [Float], modelDigest: String) -> Float? {
        guard version == 1, self.modelDigest == modelDigest, samples.count >= 5 else { return nil }
        let scores = samples.compactMap { Embeddings.cosine($0, vector) }
        guard scores.count == samples.count else { return nil }
        // Median avoids allowing a single poor enrollment outlier to dominate.
        return scores.sorted()[scores.count / 2]
    }
}

/// App-level demonstration gate, not a replacement for macOS authentication.
/// A randomized head-turn challenge is a basic motion check, not validated anti-spoofing.
public struct RecognitionGate {
    public enum Phase: String { case center, turn, returnToCenter, verified }
    public private(set) var phase: Phase = .center
    public let direction: Double
    private var consecutive = 0
    private var started: TimeInterval?
    private var lastFrame: TimeInterval?

    public init(direction: Double = Bool.random() ? 1 : -1) {
        self.direction = direction >= 0 ? 1 : -1
    }

    public mutating func reset() {
        phase = .center; consecutive = 0; started = nil; lastFrame = nil
    }

    public mutating func observe(similarity: Float?, threshold: Float, yaw: Double,
                                 faceCount: Int, timestamp: TimeInterval) -> Bool {
        guard threshold.isFinite, (0.5...0.95).contains(threshold), timestamp.isFinite,
              yaw.isFinite, faceCount == 1, let similarity, similarity.isFinite,
              similarity >= threshold else { reset(); return false }
        if let lastFrame, timestamp <= lastFrame || timestamp - lastFrame > 1 {
            reset()
        }
        if let started, timestamp - started > 12 { reset() }
        if started == nil { started = timestamp }
        lastFrame = timestamp
        let poseMatches: Bool
        switch phase {
        case .center, .returnToCenter: poseMatches = abs(yaw) < 0.14
        case .turn: poseMatches = yaw * direction > 0.24 && abs(yaw) < 0.65
        case .verified: return true
        }
        consecutive = poseMatches ? consecutive + 1 : 0
        guard consecutive >= 3 else { return false }
        consecutive = 0
        switch phase {
        case .center: phase = .turn
        case .turn: phase = .returnToCenter
        case .returnToCenter: phase = .verified
        case .verified: break
        }
        return phase == .verified
    }
}
