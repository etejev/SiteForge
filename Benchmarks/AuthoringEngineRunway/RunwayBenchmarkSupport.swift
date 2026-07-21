import Darwin
import Foundation

struct RunwayPercentiles: Codable, Sendable {
    let p50Milliseconds: Double
    let p95Milliseconds: Double
    let minimumMilliseconds: Double
    let maximumMilliseconds: Double
}

struct RunwayMeasurement: Codable, Sendable {
    let domain: String
    let alternative: String
    let operation: String
    let fixtureCount: Int
    let warmupCount: Int
    let repetitionCount: Int
    let timing: RunwayPercentiles
    let samplesMilliseconds: [Double]
    let samplesOver16_67Milliseconds: Int
    let residentBytesBefore: UInt64
    let residentBytesAfter: UInt64
    let processPeakResidentBytes: UInt64
    let deterministicDigest: String?
    let notes: [String]
}

struct RunwayCorrectnessEvidence: Codable, Sendable {
    let coordinateMaximumRoundTripError: Double
    let zoomAnchorMaximumError: Double
    let panDeltaMaximumError: Double
    let overlayContentDigestUnchanged: Bool
    let nativeMaterialPassThrough: Bool
    let browserParityMaximumPointError: Double
    let browserParityWidths: [Double]
    let largeFixtureBrowserParityMaximumPointError: [String: Double]
    let repeatedLayoutDigestStable: Bool
    let invalidInputRejected: Bool
    let unsupportedInputRejected: Bool
    let cancellationObserved: Bool
    let staleResultRejected: Bool
    let metalAvailable: Bool
}

struct RunwayEnvironment: Codable, Sendable {
    let hardwareModel: String
    let architecture: String
    let physicalMemoryBytes: UInt64
    let macOSVersion: String
    let xcodeVersion: String
    let sdkVersion: String
    let swiftVersion: String
    let buildConfiguration: String
}

struct RunwayResourceEvidence: Codable, Sendable {
    let resourceCount: Int
    let bytesPerResource: Int
    let totalResourceBytes: Int
    let deterministicIndex: Bool
    let encodedIndexBytes: Int
    let encodedControlPackageBytes: Int
    let packageParserLimitBytes: Int
    let lazyReadMatched: Bool
    let fixtureConstructionExcludedFromCanvasAndLayoutMeasurements: Bool
}

struct RunwayReport: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let sourceBaseRevision: String
    let configuration: [String: String]
    let environment: RunwayEnvironment
    let correctness: RunwayCorrectnessEvidence
    let resourceEvidence: RunwayResourceEvidence
    let measurements: [RunwayMeasurement]
    let limitations: [String]
}

enum RunwayBenchmark {
    static func measure(
        domain: String,
        alternative: String,
        operation: String,
        fixtureCount: Int,
        warmups: Int,
        repetitions: Int,
        digest: String? = nil,
        notes: [String] = [],
        body: () throws -> Void
    ) rethrows -> RunwayMeasurement {
        for _ in 0..<warmups { try autoreleasepool { try body() } }
        let residentBefore = residentBytes()
        var samples: [Double] = []
        samples.reserveCapacity(repetitions)
        for _ in 0..<repetitions {
            let start = ContinuousClock.now
            try autoreleasepool { try body() }
            let elapsed = start.duration(to: .now)
            samples.append(milliseconds(elapsed))
        }
        let residentAfter = residentBytes()
        let sorted = samples.sorted()
        return RunwayMeasurement(
            domain: domain,
            alternative: alternative,
            operation: operation,
            fixtureCount: fixtureCount,
            warmupCount: warmups,
            repetitionCount: repetitions,
            timing: RunwayPercentiles(
                p50Milliseconds: percentile(sorted, 0.50),
                p95Milliseconds: percentile(sorted, 0.95),
                minimumMilliseconds: sorted.first ?? 0,
                maximumMilliseconds: sorted.last ?? 0
            ),
            samplesMilliseconds: samples,
            samplesOver16_67Milliseconds: samples.filter { $0 > 16.67 }.count,
            residentBytesBefore: residentBefore,
            residentBytesAfter: residentAfter,
            processPeakResidentBytes: peakResidentBytes(),
            deterministicDigest: digest,
            notes: notes
        )
    }

    @MainActor
    static func measureAsync(
        domain: String,
        alternative: String,
        operation: String,
        fixtureCount: Int,
        warmups: Int,
        repetitions: Int,
        digest: String? = nil,
        notes: [String] = [],
        body: () async throws -> Void
    ) async rethrows -> RunwayMeasurement {
        for _ in 0..<warmups { try await body() }
        let residentBefore = residentBytes()
        var samples: [Double] = []
        samples.reserveCapacity(repetitions)
        for _ in 0..<repetitions {
            let start = ContinuousClock.now
            try await body()
            let elapsed = start.duration(to: .now)
            samples.append(milliseconds(elapsed))
        }
        let residentAfter = residentBytes()
        let sorted = samples.sorted()
        return RunwayMeasurement(
            domain: domain,
            alternative: alternative,
            operation: operation,
            fixtureCount: fixtureCount,
            warmupCount: warmups,
            repetitionCount: repetitions,
            timing: RunwayPercentiles(
                p50Milliseconds: percentile(sorted, 0.50),
                p95Milliseconds: percentile(sorted, 0.95),
                minimumMilliseconds: sorted.first ?? 0,
                maximumMilliseconds: sorted.last ?? 0
            ),
            samplesMilliseconds: samples,
            samplesOver16_67Milliseconds: samples.filter { $0 > 16.67 }.count,
            residentBytesBefore: residentBefore,
            residentBytesAfter: residentAfter,
            processPeakResidentBytes: peakResidentBytes(),
            deterministicDigest: digest,
            notes: notes
        )
    }

    static func environment() -> RunwayEnvironment {
        RunwayEnvironment(
            hardwareModel: sysctlString("hw.model"),
            architecture: command("/usr/bin/uname", ["-m"]),
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            macOSVersion: command("/usr/bin/sw_vers", ["-productVersion"]),
            xcodeVersion: command("/usr/bin/xcodebuild", ["-version"]).replacingOccurrences(of: "\n", with: "; "),
            sdkVersion: command("/usr/bin/xcrun", ["--show-sdk-version"]),
            swiftVersion: command("/usr/bin/xcrun", ["swiftc", "--version"]).replacingOccurrences(of: "\n", with: "; "),
            buildConfiguration: "swiftc -O -swift-version 6"
        )
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func peakResidentBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(ceil(Double(sorted.count) * fraction)) - 1
        return sorted[max(0, min(sorted.count - 1, index))]
    }

    private static func sysctlString(_ key: String) -> String {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        let content = bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: content, as: UTF8.self)
    }

    private static func command(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "unavailable" }
            return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unavailable"
        } catch {
            return "unavailable"
        }
    }
}
