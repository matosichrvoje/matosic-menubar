import Foundation

/// Byte-level constants and encoders for the Mac↔macropad Raw HID
/// conversation. The Mac drives the device's default layer in response
/// to macOS focus changes by piggy-backing on VIA's "custom channel"
/// command framing — that way VIA's own protocol stays untouched and
/// the web configurator (matosic-macropad-web/public/configure.js)
/// keeps working unchanged against the same Raw HID interface.
///
/// Wire format (32-byte Raw HID report, no report ID prefix):
///
///   SET layer N:
///     [0x07, 0x10, 0x00, N, 0, 0, ...] →
///     device replies (in place):
///     [0x07, 0x10, 0x00, N, 0, 0, ...]   on success
///     [0xFF, 0x10, 0x00, N, 0, 0, ...]   on rejection (FN reserved /
///                                         out-of-range layer)
///
///   GET active layer:
///     [0x08, 0x10, 0x00, 0, 0, ...] →
///     [0x08, 0x10, 0x00, currentLayer, ...]
///
/// The 0x07/0x08 command IDs are VIA's id_custom_set_value /
/// id_custom_get_value. The 0x10 channel ID identifies our "menubar"
/// channel inside that framing (see firmware/qmk/keyboards/matosic/
/// macropad/macropad.c `via_custom_value_command_kb`).
enum MacropadProtocol {
    static let vendorID:  UInt16 = 0xFEED
    static let productID: UInt16 = 0x0001

    /// Same usage page + usage configure.js filters on. On macOS the
    /// composite device exposes the keyboard, consumer-control, and
    /// raw-HID interfaces as separate IOHIDDevice instances — we want
    /// the one matching these.
    static let rawHidUsagePage: UInt32 = 0xFF60
    static let rawHidUsage:     UInt32 = 0x61

    static let reportLength = 32

    // Layer-range invariants enforced on the firmware side. Index 1
    // (FN) is a momentary overlay (`MO(_FN)`) — never a destination.
    // `maxLayerIndex` matches `DYNAMIC_KEYMAP_LAYER_COUNT - 1` in
    // firmware/qmk/keyboards/matosic/macropad/config.h.
    static let reservedFnLayerIndex = 1
    static let maxLayerIndex = 5

    enum CommandID: UInt8 {
        case customSetValue = 0x07
        case customGetValue = 0x08
        case unhandled      = 0xFF
    }

    static let menubarChannelID: UInt8 = 0x10

    enum MenubarValueID: UInt8 {
        case activeLayer = 0x00
    }

    /// Encode a SET_ACTIVE_LAYER request. Refuses layer 1 (FN reserved)
    /// up-front so we never even put it on the wire.
    static func encodeSetActiveLayer(_ layerIndex: Int) -> Data? {
        guard (0...maxLayerIndex).contains(layerIndex),
              layerIndex != reservedFnLayerIndex else {
            return nil
        }
        var buf = [UInt8](repeating: 0, count: reportLength)
        buf[0] = CommandID.customSetValue.rawValue
        buf[1] = menubarChannelID
        buf[2] = MenubarValueID.activeLayer.rawValue
        buf[3] = UInt8(layerIndex)
        return Data(buf)
    }

    /// Encode a GET_ACTIVE_LAYER request.
    static func encodeGetActiveLayer() -> Data {
        var buf = [UInt8](repeating: 0, count: reportLength)
        buf[0] = CommandID.customGetValue.rawValue
        buf[1] = menubarChannelID
        buf[2] = MenubarValueID.activeLayer.rawValue
        return Data(buf)
    }

    /// Result of parsing a Raw HID input report.
    enum ResponseParse {
        /// Echo of a SET we sent. Useful as an ACK.
        case setAck(layer: Int)
        /// Reply to a GET. `layer` is the device's current default layer.
        case getReply(layer: Int)
        /// Device rejected our command (FN slot, out-of-range, or wrong
        /// channel). Carries the original command id so the caller can
        /// pair it with the in-flight request.
        case rejected
        /// Anything else — probably a stray VIA response or an event we
        /// don't model. Caller can ignore.
        case unknown
    }

    static func parseResponse(_ data: Data) -> ResponseParse {
        guard data.count >= 4 else { return .unknown }
        let bytes = [UInt8](data)
        let cmd     = bytes[0]
        let channel = bytes[1]
        let value   = bytes[2]
        let payload = bytes[3]

        guard channel == menubarChannelID,
              value   == MenubarValueID.activeLayer.rawValue else {
            return .unknown
        }
        switch cmd {
        case CommandID.customSetValue.rawValue:
            return .setAck(layer: Int(payload))
        case CommandID.customGetValue.rawValue:
            return .getReply(layer: Int(payload))
        case CommandID.unhandled.rawValue:
            return .rejected
        default:
            return .unknown
        }
    }
}
