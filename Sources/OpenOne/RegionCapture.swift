import AppKit
import Foundation

enum CaptureError: LocalizedError {
    case permission, failed(String), invalidImage
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow Open One in System Settings → Privacy & Security → Screen Recording, then quit and reopen Open One. If access is already on after a development rebuild, remove Open One from that list and add this build again."
        case .failed(let detail): return "The screenshot could not be captured. \(detail)"
        case .invalidImage: return "The captured file was not a valid PNG image."
        }
    }
}

@MainActor final class RegionCapture {
    private var process: Process?
    private let executable: URL
    private let permissionGranted: () -> Bool
    private let requestPermission: () -> Void
    init(executable: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"), permissionGranted: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }, requestPermission: @escaping () -> Void = { CGRequestScreenCaptureAccess() }) {
        self.executable = executable; self.permissionGranted = permissionGranted; self.requestPermission = requestPermission
    }
    /// Check before hiding the composer, so permission errors stay visible.
    func ensurePermission() throws {
        if !permissionGranted() {
            requestPermission()
            guard permissionGranted() else { throw CaptureError.permission }
        }
    }
    func capture(to directory: URL) async throws -> URL? {
        try Task.checkCancellation()
        guard process == nil else { return nil }
        try ensurePermission()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent("capture-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-i", "-x", "-t", "png", destination.path]
        process.standardOutput = FileHandle.nullDevice
        // A file avoids blocking a child on a full stderr pipe.
        let errorURL = directory.appendingPathComponent(".capture-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errors = try FileHandle(forWritingTo: errorURL)
        process.standardError = errors
        self.process = process
        var keepCapture = false
        defer {
            self.process = nil
            try? errors.close()
            try? FileManager.default.removeItem(at: errorURL)
            if !keepCapture { try? FileManager.default.removeItem(at: destination) }
        }
        let status: Int32 = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { child in continuation.resume(returning: child.terminationStatus) }
                do { try process.run() }
                catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                if self?.process === process, process.isRunning { process.terminate() }
            }
        })
        try Task.checkCancellation()
        let detail = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Escape is cancellation, never an empty attachment or a send action.
        guard FileManager.default.fileExists(atPath: destination.path) else {
            if (status == 0 || status == 1) && detail.isEmpty { return nil }
            throw CaptureError.failed(String(detail.suffix(1000)))
        }
        guard status == 0 else { throw CaptureError.failed(String(detail.suffix(1000))) }
        guard NSImage(contentsOf: destination) != nil else { try? FileManager.default.removeItem(at: destination); throw CaptureError.invalidImage }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        keepCapture = true
        return destination
    }
    func cancel() { if let process, process.isRunning { process.terminate() } }
}
