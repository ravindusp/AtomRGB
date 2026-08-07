import AtomProtocol
import Foundation
import HIDTransport

private let defaultVendorID = 0x5566
private let defaultProductID = 0x0008

private enum Command: Sendable {
    case info
    case state
    case mutation(Mutation)
}

private enum Mutation: Sendable {
    case staticColor(RGBColor)
    case brightness(UInt8)
    case effect(LightingEffect)
    case speed(LightingSpeed)
    case direction(DirectionFlag)
    case colorful(Bool)

    func apply(to state: inout AtomLightingState) {
        switch self {
        case .staticColor(let color):
            state.effect = .staticRGB
            state.color = color
            state.colorful = false
        case .brightness(let value):
            state.brightness = value
        case .effect(let effect):
            state.effect = effect
        case .speed(let speed):
            state.speed = speed
        case .direction(let direction):
            state.direction = direction
        case .colorful(let enabled):
            state.colorful = enabled
        }
    }
}

private struct Invocation {
    let write: Bool
    let command: Command
}

@main
private struct AtomCLI {
    static func main() async {
        do {
            let invocation = try parseInvocation(Array(CommandLine.arguments.dropFirst()))
            try await run(invocation)
        } catch {
            fputs("atomctl: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ invocation: Invocation) async throws {
        switch invocation.command {
        case .info:
            printInfo()
        case .state:
            let transport = try AtomHIDTransport.open(logger: logger)
            let service = AtomLightingService(transport: transport)
            let state = try await service.refresh()
            printState(state)
        case .mutation(let mutation):
            if invocation.write {
                let transport = try AtomHIDTransport.open(logger: logger)
                let service = AtomLightingService(transport: transport)
                let state = try await service.apply { mutation.apply(to: &$0) }
                print("Applied successfully.")
                printState(state)
            } else {
                try printDryRun(for: mutation)
            }
        }
    }

    private static func printInfo() {
        let devices = HIDDeviceEnumerator().enumerate(
            vendorID: defaultVendorID,
            productID: defaultProductID
        )
        if devices.isEmpty {
            print(String(format: "No HID collections found for VID 0x%04X PID 0x%04X.", defaultVendorID, defaultProductID))
            return
        }

        print(String(format: "Found %d HID collection(s) for VID 0x%04X PID 0x%04X", devices.count, defaultVendorID, defaultProductID))
        for (index, device) in devices.enumerated() {
            print("\nCollection \(index + 1)")
            print(String(format: "  VID/PID:       0x%04X:0x%04X", device.vendorID, device.productID))
            print("  Manufacturer:  \(device.manufacturer ?? "-")")
            print("  Product:       \(device.product ?? "-")")
            print("  Serial:        \(device.serialNumber ?? "-")")
            print(String(format: "  Usage:         0x%04X / 0x%04X", device.usagePage ?? 0, device.usage ?? 0))
            print("  Interface:     \(device.interfaceNumber.map(String.init) ?? "-")")
            print("  Input report:  \(device.maxInputReportSize.map(String.init) ?? "-") bytes")
            print("  Output report: \(device.maxOutputReportSize.map(String.init) ?? "-") bytes")
            print("  Feature report:\(device.maxFeatureReportSize.map { " \($0)" } ?? " -") bytes")
            print("  Registry ID:   \(device.registryID.map(String.init) ?? "-")")
            print("  Descriptor SHA: \(device.reportDescriptorSHA256 ?? "-")")
        }
    }

    private static func printDryRun(for mutation: Mutation) throws {
        var state = try dryRunState()
        mutation.apply(to: &state)
        let set = try AtomProtocol.makeSetFrame(from: state)

        print("DRY RUN: no HID device opened and no report sent.")
        print("Base state: captured Static Red fixture.")
        printFrame("TX", AtomProtocol.makeSimpleCommand(.beginTransaction))
        print("RX expected: AA 01 ...")
        printFrame("TX", AtomProtocol.makeGetLightingRequest())
        print("RX expected: AA 05 ... current state")
        printFrame("TX", set)
        print("RX expected: AA 06 ... SET echo")
        printFrame("TX", AtomProtocol.makeSimpleCommand(.commitTransaction))
        print("RX expected: AA 02 ...")
        printState(state)
    }

    private static func dryRunState() throws -> AtomLightingState {
        var frame = staticRedFixture()
        frame[0] = AtomProtocol.deviceMarker
        frame[1] = AtomProtocol.Command.getLighting.rawValue
        frame[3] = AtomProtocol.checksum(frame)
        return try AtomProtocol.parseLightingState(frame)
    }

    private static func staticRedFixture() -> [UInt8] {
        [
            0x55, 0x06, 0x00, 0x6B, 0x20, 0x00, 0x00, 0x00,
            0x02, 0xAA, 0x03, 0x64, 0x01, 0x00, 0x00, 0x00,
            0xFF, 0x00, 0x00, 0x00, 0x64, 0x04, 0x00, 0xCB,
            0x04, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
    }

    private static func printState(_ state: AtomLightingState) {
        print(String(format: "State: effect=%@ brightness=%d speed=0x%02X direction=0x%02X colorful=%@ rgb=%02X%02X%02X",
                     state.effect.displayName,
                     state.brightness,
                     state.speed.rawValue,
                     state.direction.rawValue,
                     state.colorful ? "on" : "off",
                     state.color.red,
                     state.color.green,
                     state.color.blue))
    }

    private static func printFrame(_ prefix: String, _ bytes: [UInt8]) {
        print("\(prefix): \(hex(bytes))")
    }

    private static let logger: @Sendable (String) -> Void = { message in
        print("[AtomRGB] \(message)")
    }

    private static func parseInvocation(_ arguments: [String]) throws -> Invocation {
        var arguments = arguments
        var write = false
        var dryRun = false

        arguments.removeAll { argument in
            if argument == "--write" {
                write = true
                return true
            }
            if argument == "--dry-run" {
                dryRun = true
                return true
            }
            return false
        }

        if write && dryRun {
            throw CLIError.message("--write and --dry-run cannot be combined")
        }
        guard let command = arguments.first else {
            throw CLIError.usage
        }

        switch command.lowercased() {
        case "info":
            guard arguments.count == 1 else { throw CLIError.usage }
            return Invocation(write: false, command: .info)
        case "state":
            guard arguments.count == 1 else { throw CLIError.usage }
            return Invocation(write: false, command: .state)
        case "static":
            guard arguments.count == 2, let color = parseRGB(arguments[1]) else {
                throw CLIError.message("static expects a six-digit RRGGBB value")
            }
            return Invocation(write: write, command: .mutation(.staticColor(color)))
        case "brightness":
            guard arguments.count == 2, let value = Int(arguments[1]), (0...100).contains(value) else {
                throw CLIError.message("brightness expects an integer from 0 through 100")
            }
            return Invocation(write: write, command: .mutation(.brightness(UInt8(value))))
        case "effect":
            guard arguments.count == 2, let effect = parseEffect(arguments[1]) else {
                throw CLIError.message("unknown lighting effect")
            }
            return Invocation(write: write, command: .mutation(.effect(effect)))
        case "speed":
            guard arguments.count == 2, let speed = parseSpeed(arguments[1]) else {
                throw CLIError.message("speed expects maximum, fast, medium, slow, or minimum")
            }
            return Invocation(write: write, command: .mutation(.speed(speed)))
        case "direction":
            guard arguments.count == 2, let direction = parseDirection(arguments[1]) else {
                throw CLIError.message("direction expects normal or reverse")
            }
            return Invocation(write: write, command: .mutation(.direction(direction)))
        case "colorful":
            guard arguments.count == 2 else { throw CLIError.message("colorful expects on or off") }
            switch arguments[1].lowercased() {
            case "on": return Invocation(write: write, command: .mutation(.colorful(true)))
            case "off": return Invocation(write: write, command: .mutation(.colorful(false)))
            default: throw CLIError.message("colorful expects on or off")
            }
        case "help", "--help", "-h":
            throw CLIError.usage
        default:
            throw CLIError.usage
        }
    }

    private static func parseRGB(_ value: String) -> RGBColor? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 6 else { return nil }
        let characters = Array(value)
        guard let red = UInt8(String(characters[0...1]), radix: 16),
              let green = UInt8(String(characters[2...3]), radix: 16),
              let blue = UInt8(String(characters[4...5]), radix: 16) else {
            return nil
        }
        return RGBColor(red: red, green: green, blue: blue)
    }

    private static func parseEffect(_ value: String) -> LightingEffect? {
        if let raw = parseInteger(value), let effect = LightingEffect(rawValue: UInt8(clamping: raw)) {
            return effect
        }
        let normalized = normalize(value)
        return LightingEffect.allCases.first { normalize($0.displayName) == normalized || normalize(String(describing: $0)) == normalized }
    }

    private static func parseSpeed(_ value: String) -> LightingSpeed? {
        if let raw = parseInteger(value), (0...4).contains(raw) {
            return LightingSpeed(rawValue: UInt8(raw))
        }
        switch normalize(value) {
        case "maximum": return .maximum
        case "fast": return .fast
        case "medium": return .medium
        case "slow": return .slow
        case "minimum": return .minimum
        default: return nil
        }
    }

    private static func parseDirection(_ value: String) -> DirectionFlag? {
        switch normalize(value) {
        case "normal", "0": return .normal
        case "reverse", "1": return .reverse
        default: return nil
        }
    }

    private static func parseInteger(_ value: String) -> Int? {
        if value.lowercased().hasPrefix("0x") {
            return Int(value.dropFirst(2), radix: 16)
        }
        return Int(value)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return """
            Usage:
              atomctl info
              atomctl state
              atomctl [--dry-run|--write] static RRGGBB
              atomctl [--dry-run|--write] brightness 0...100
              atomctl [--dry-run|--write] effect <effect>
              atomctl [--dry-run|--write] speed <maximum|fast|medium|slow|minimum>
              atomctl [--dry-run|--write] direction <normal|reverse>
              atomctl [--dry-run|--write] colorful <on|off>

            Mutating commands are dry-run by default. Use --write to send reports.
            """
        case .message(let message): return "\(message)\n\(CLIError.usage.description)"
        }
    }
}
