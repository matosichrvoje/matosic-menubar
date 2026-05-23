import Foundation
import Combine
import IOKit
import IOKit.hid

/// Owns the IOHIDManager that watches for the macropad's Raw HID
/// interface, opens it when it appears, and sends VIA custom-channel
/// commands to drive the device's active layer in response to macOS
/// focus changes. Publishes connection state + last-known device layer
/// for the SwiftUI popover to render.
///
/// **Threading.** Everything runs on the main RunLoop. The IOKit work
/// per focus change is a single ~5ms `IOHIDDeviceSetReport`, fast enough
/// that main-thread is fine and avoids the dispatch-queue API's
/// ordering pitfalls (which proved brittle: setting up async support
/// twice crashes IOKit, but skipping it crashes IOKit too — the runloop
/// API just doesn't have this trap).
///
/// **No request tracking.** SETs are fire-and-forget. GET replies arrive
/// asynchronously and update `deviceLayer` when they land. IOKit's
/// device-removal callback is the authoritative "device went away"
/// signal.
@MainActor
final class DeviceController: ObservableObject {
    @Published private(set) var isConnected: Bool = false
    /// The most recent layer index reported by the device (via GET reply
    /// or echoed SET ack). `nil` until we've seen a response.
    @Published private(set) var deviceLayer: Int? = nil

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var inputBuffer = [UInt8](repeating: 0, count: MacropadProtocol.reportLength)

    init() {
        startManager()
    }

    // MARK: - Public commands

    /// Set the device's active default layer. No-op when disconnected
    /// (the caller — typically the focus→device bridge in AppDelegate —
    /// re-fires the right layer on reconnect, so dropping in-flight
    /// SETs is safe).
    func setLayer(_ layerIndex: Int) {
        guard let device else { return }
        guard let payload = MacropadProtocol.encodeSetActiveLayer(layerIndex) else {
            FileHandle.standardError.write(Data("[matosic-menubar] refusing to SET reserved/out-of-range layer \(layerIndex)\n".utf8))
            return
        }
        sendReport(device: device, payload: payload)
    }

    /// Ask the device which layer is currently active. The reply, when
    /// it arrives, updates `deviceLayer`.
    func refreshLayer() {
        guard let device else { return }
        sendReport(device: device, payload: MacropadProtocol.encodeGetActiveLayer())
    }

    // MARK: - Manager / matching setup

    private func startManager() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String:        Int(MacropadProtocol.vendorID),
            kIOHIDProductIDKey as String:       Int(MacropadProtocol.productID),
            kIOHIDPrimaryUsagePageKey as String: Int(MacropadProtocol.rawHidUsagePage),
            kIOHIDPrimaryUsageKey as String:     Int(MacropadProtocol.rawHidUsage),
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.matchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager,  Self.removalCallback,  context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            FileHandle.standardError.write(Data("[matosic-menubar] IOHIDManagerOpen failed: \(openResult)\n".utf8))
        }
    }

    // MARK: - C callbacks (free functions; bounce back to instance via context)

    private static let matchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let controller = Unmanaged<DeviceController>.fromOpaque(context).takeUnretainedValue()
        // Callbacks fire on the main runloop (we scheduled the manager
        // there), so we're already on the MainActor — assumeIsolated keeps
        // the type system honest without an unnecessary hop.
        MainActor.assumeIsolated {
            controller.handleDeviceArrival(device)
        }
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let controller = Unmanaged<DeviceController>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            controller.handleDeviceRemoval(device)
        }
    }

    private static let inputCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
        guard let context else { return }
        let controller = Unmanaged<DeviceController>.fromOpaque(context).takeUnretainedValue()
        let data = Data(bytes: report, count: length)
        MainActor.assumeIsolated {
            controller.handleInputReport(data)
        }
    }

    // MARK: - Device lifecycle

    private func handleDeviceArrival(_ device: IOHIDDevice) {
        if let existing = self.device, existing !== device {
            IOHIDDeviceClose(existing, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            FileHandle.standardError.write(Data("[matosic-menubar] IOHIDDeviceOpen failed: \(openResult)\n".utf8))
            return
        }
        self.device = device

        let context = Unmanaged.passUnretained(self).toOpaque()
        inputBuffer.withUnsafeMutableBufferPointer { ptr in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                ptr.baseAddress!,
                CFIndex(MacropadProtocol.reportLength),
                Self.inputCallback,
                context
            )
        }
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        isConnected = true
        // Sync up — find out what layer the device is on so the HUD is
        // honest immediately.
        refreshLayer()
    }

    private func handleDeviceRemoval(_ device: IOHIDDevice) {
        if self.device === device {
            self.device = nil
            isConnected = false
            deviceLayer = nil
        }
    }

    private func handleInputReport(_ data: Data) {
        switch MacropadProtocol.parseResponse(data) {
        case .getReply(let layer), .setAck(let layer):
            deviceLayer = layer
        case .rejected:
            FileHandle.standardError.write(Data("[matosic-menubar] device rejected menubar command\n".utf8))
        case .unknown:
            // Probably a VIA reply destined for the web configurator if
            // it's running concurrently — ignore.
            break
        }
    }

    // MARK: - Send

    private func sendReport(device: IOHIDDevice, payload: Data) {
        payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            let result = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(0),  // report ID 0; QMK Raw HID doesn't use a separate ID
                base,
                CFIndex(payload.count)
            )
            if result != kIOReturnSuccess {
                FileHandle.standardError.write(Data("[matosic-menubar] setReport failed: \(result)\n".utf8))
            }
        }
    }
}
