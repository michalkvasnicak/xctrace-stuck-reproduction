import CryptoKit
import Foundation

enum ProfilerWorkload {
    static func run() async -> String {
        let workerCount = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
        let iterationsPerWorker = 75_000

        let combined = await withTaskGroup(of: UInt64.self) { group in
            for workerIndex in 0..<workerCount {
                group.addTask(priority: .userInitiated) {
                    runWorker(index: workerIndex, iterations: iterationsPerWorker)
                }
            }

            var combined = UInt64(0xcbf29ce484222325)
            for await workerResult in group {
                combined = (combined &* 0x100000001b3) ^ workerResult
            }
            return combined
        }

        return String(format: "%016llx", combined)
    }

    private static func runWorker(index: Int, iterations: Int) -> UInt64 {
        var accumulator = UInt64(index + 1)

        for iteration in 0..<iterations {
            let input = "\(index)-\(iteration)-\(UUID().uuidString)-\(accumulator)"
            let digest = SHA256.hash(data: Data(input.utf8))

            for byte in digest {
                accumulator = (accumulator &* 0x100000001b3) ^ UInt64(byte)
            }
        }

        return accumulator
    }
}
