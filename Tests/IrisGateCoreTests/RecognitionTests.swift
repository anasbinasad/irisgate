import Testing
@testable import IrisGateCore

struct RecognitionTests {
    @Test func testEmbeddingValidationAndCosine() {
        #expect(Embeddings.normalize([]) == nil)
        #expect(Embeddings.normalize([0, 0]) == nil)
        #expect(Embeddings.normalize([.nan, 1]) == nil)
        #expect(Embeddings.cosine([1], [1, 2]) == nil)
        #expect(abs(Embeddings.cosine([3, 4], [6, 8])! - 1) < 0.00001)
        #expect(abs(Embeddings.cosine([1, 0], [0, 1])!) < 0.00001)
    }

    @Test func testEnrollmentBoundToModelAndMedian() {
        let record = Enrollment(modelDigest: "a", samples: [[1, 0], [1, 0], [1, 0], [1, 0], [0, 1]])
        #expect(record.similarity(to: [1, 0], modelDigest: "b") == nil)
        #expect(record.similarity(to: [1, 0], modelDigest: "a") == 1)
        #expect(record.similarity(to: [1], modelDigest: "a") == nil)
        #expect(Enrollment(modelDigest: "a", samples: [[1, 0]]).similarity(to: [1, 0], modelDigest: "a") == nil)
    }

    @Test func testChallengeRequiresCorrectOrderedPoses() {
        var gate = RecognitionGate(direction: 1)
        var time = 100.0
        func feed(_ yaw: Double) -> Bool {
            time += 0.2
            return gate.observe(similarity: 0.9, threshold: 0.72, yaw: yaw, faceCount: 1, timestamp: time)
        }
        for _ in 0..<6 { #expect(!feed(0.3)) }
        #expect(gate.phase == .center)
        for _ in 0..<3 { #expect(!feed(0)) }
        #expect(gate.phase == .turn)
        for _ in 0..<3 { #expect(!feed(-0.3)) }
        #expect(gate.phase == .turn)
        for _ in 0..<3 { #expect(!feed(0.3)) }
        #expect(gate.phase == .returnToCenter)
        #expect(!feed(0)); #expect(!feed(0)); #expect(feed(0))
    }

    @Test func testChallengeResetsOnMismatchMultipleFacesAndStaleFrames() {
        for failure in 0..<4 {
            var gate = RecognitionGate(direction: -1)
            for i in 0..<3 {
                _ = gate.observe(similarity: 0.9, threshold: 0.72, yaw: 0, faceCount: 1, timestamp: 10 + Double(i) * 0.2)
            }
            #expect(gate.phase == .turn)
            let result = gate.observe(similarity: failure == 0 ? 0.1 : failure == 3 ? .nan : 0.9,
                threshold: 0.72, yaw: -0.3, faceCount: failure == 1 ? 2 : 1,
                timestamp: failure == 2 ? 15 : 10.8)
            #expect(!result); #expect(gate.phase == .center)
        }
    }

    @Test func testChallengeExpiresAndRejectsUnsafeThresholds() {
        var gate = RecognitionGate(direction: -1)
        for i in 0..<20 {
            _ = gate.observe(similarity: 0.9, threshold: 0.72, yaw: 0, faceCount: 1, timestamp: Double(i) * 0.7)
        }
        #expect(gate.phase == .center)
        let result = gate.observe(similarity: 1, threshold: 0.1, yaw: 0, faceCount: 1, timestamp: 20)
        #expect(!result)
        #expect(gate.phase == .center)
    }
}
