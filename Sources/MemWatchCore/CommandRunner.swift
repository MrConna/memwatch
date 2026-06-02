import Foundation

public protocol CommandRunning {
    func run(_ command: String) throws -> String
}

public struct ShellCommandRunner: CommandRunning {
    public init() {}

    public func run(_ command: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandError(command: command, status: process.terminationStatus, message: error.isEmpty ? output : error)
        }

        return output
    }
}

public struct CommandError: Error, LocalizedError {
    public var command: String
    public var status: Int32
    public var message: String

    public var errorDescription: String? {
        "\(command) failed with status \(status): \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
