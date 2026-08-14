import AVFoundation
import AppCore
import AppKit
import ApplicationServices
import Foundation
import Speech
import UserNotifications

/// Talks to TCC / the relevant framework for each ``PermissionKind``.
public struct LivePermissionChecker: PermissionChecking {
    public init() {}

    public func status(of permission: PermissionKind) -> PermissionStatus {
        switch permission {
        case .accessibility:
            AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            CGPreflightListenEventAccess() ? .granted : .denied
        case .fullDiskAccess:
            fullDiskAccessStatus()
        case .microphone:
            microphoneStatus()
        case .speechRecognition:
            speechStatus()
        case .notifications:
            // UNUserNotificationCenter.status is async; treat as undetermined
            // until request() is called. Doctor uses the async path.
            .notDetermined
        }
    }

    public func request(_ permission: PermissionKind) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
            return CGPreflightListenEventAccess() ? .granted : .denied
        case .fullDiskAccess:
            openSettings(for: .fullDiskAccess)
            return fullDiskAccessStatus()
        case .microphone:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            return granted ? .granted : .denied
        case .speechRecognition:
            return await requestSpeech()
        case .notifications:
            return await requestNotifications()
        }
    }

    public func openSettings(for permission: PermissionKind) {
        guard let url = URL(string: permission.settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    public func notificationStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    private func speechStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }

    private func requestSpeech() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                switch status {
                case .authorized:
                    continuation.resume(returning: .granted)
                case .denied, .restricted:
                    continuation.resume(returning: .denied)
                case .notDetermined:
                    continuation.resume(returning: .notDetermined)
                @unknown default:
                    continuation.resume(returning: .notDetermined)
                }
            }
        }
    }

    private func requestNotifications() async -> PermissionStatus {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            return granted ? .granted : .denied
        } catch {
            return .denied
        }
    }

    /// FDA has no public status API. Reading a protected path is the practical
    /// check — the TCC database itself, which always exists on a working system
    /// and is never a user's private data. A missing probe means the answer is
    /// unknown, not that access was refused.
    private func fullDiskAccessStatus() -> PermissionStatus {
        let probe = URL.homeDirectory
            .appending(path: "Library/Application Support/com.apple.TCC/TCC.db")

        guard FileManager.default.fileExists(atPath: probe.path) else {
            return .notDetermined
        }

        return FileManager.default.isReadableFile(atPath: probe.path) ? .granted : .denied
    }
}
