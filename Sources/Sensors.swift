import AppKit
import CoreAudio
import CoreMediaIO
import Darwin
import Intents

/// Erkennt Videocalls und Bildschirmfreigaben – ohne Sonderrechte:
/// Ob Kamera oder Mikrofon gerade von irgendeinem Programm benutzt werden, verrät macOS jedem.
enum CallDetector {
    enum Reason {
        case camera, microphone, screenSharing

        var title: String {
            switch self {
            case .camera: return L10n.s("Kamera an", "camera on")
            case .microphone: return L10n.s("Mikrofon an", "microphone on")
            case .screenSharing: return L10n.s("Bildschirm wird geteilt", "screen is shared")
            }
        }
    }

    /// Prozesse, die nur während einer Bildschirmfreigabe laufen
    /// (macOS-Bildschirmfreigabe und Zooms Teilen-Funktion).
    private static let sharingProcesses: Set<String> = ["ScreensharingAgent", "CptHost"]

    static func currentReason() -> Reason? {
        if cameraInUse() { return .camera }
        if microphoneInUse() { return .microphone }
        if screenIsShared() { return .screenSharing }
        return nil
    }

    static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr
        else { return false }

        for device in devices where hasInput(device) {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == noErr
        else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                         &runningUsed, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    static func screenIsShared() -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(max(0, filled))) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, sharingProcesses.contains(String(cString: name)) {
                return true
            }
        }
        return false
    }
}

/// Fokus („Nicht stören“ usw.): Den Status gibt macOS nur nach Zustimmung heraus.
@MainActor
final class FocusMonitor: ObservableObject {
    enum Access { case unknown, allowed, denied, unavailable }

    @Published private(set) var access: Access = .unknown

    init() { refresh() }

    var isFocused: Bool {
        access == .allowed && (INFocusStatusCenter.default.focusStatus.isFocused ?? false)
    }

    func refresh() {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: access = .allowed
        case .denied: access = .denied
        case .restricted: access = .unavailable
        case .notDetermined: access = .unknown
        @unknown default: access = .unavailable
        }
    }

    func requestAccess() {
        INFocusStatusCenter.default.requestAuthorization { _ in
            Task { @MainActor in self.refresh() }
        }
    }
}
