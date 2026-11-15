import AppKit
import Foundation

/// Runs command-line tools. No helper tool is installed: privileged work goes through
/// a one-off macOS administrator prompt (AppleScript `with administrator privileges`).
enum Shell {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    struct AdminError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let extendedPATH: String = {
        let home = NSHomeDirectory()
        return [
            "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/.orbstack/bin", "\(home)/.docker/bin", "\(home)/.rd/bin",
            "/Applications/Docker.app/Contents/Resources/bin",
        ].joined(separator: ":")
    }()

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = extendedPATH
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain stderr concurrently so a full pipe buffer can't deadlock us.
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        killer.cancel()

        return Output(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Single-quote a string for /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Runs a shell command as root after the standard macOS password prompt.
    @MainActor
    @discardableResult
    static func runAsAdmin(_ command: String) throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw AdminError(message: "Could not build AppleScript")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw AdminError(message: message)
        }
        return result.stringValue ?? ""
    }
}
