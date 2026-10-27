import Foundation

enum ProcessRunner {
    nonisolated static func output(of executable: URL, arguments: [String], in directory: URL? = nil, timeout: Duration = .seconds(90)) async -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let watchdog = Task.detached {
            try? await Task.sleep(for: timeout)
            process.terminate()
        }
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit()
        watchdog.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}
