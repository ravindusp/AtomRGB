import Foundation

public enum AtomProtocol {
    public static let frameLength = 64
    public static let hostMarker: UInt8 = 0x55
    public static let deviceMarker: UInt8 = 0xAA
    public static let rgbInterfaceNumber = 2
    public static let rgbOutputEndpoint: UInt8 = 0x05
    public static let rgbInputEndpoint: UInt8 = 0x85

    public enum Command: UInt8, CaseIterable, Sendable {
        case beginTransaction = 0x01
        case commitTransaction = 0x02
        case getLighting = 0x05
        case setLighting = 0x06
    }

    public enum Offset {
        public static let marker = 0
        public static let command = 1
        public static let reserved = 2
        public static let checksum = 3
        public static let statePrefix = 4
        public static let effect = 10
        public static let brightness = 11
        public static let speed = 12
        public static let direction = 13
        public static let colorful = 14
        public static let red = 16
        public static let green = 17
        public static let blue = 18
    }

    public static func checksum(_ packet: [UInt8]) -> UInt8 {
        precondition(packet.count == frameLength, "Atom protocol frames must be 64 bytes")

        var sum: UInt16 = 0
        for byte in packet[4..<frameLength] {
            sum += UInt16(byte)
        }
        return UInt8(truncatingIfNeeded: sum)
    }

    public static func makeSimpleCommand(_ command: Command) -> [UInt8] {
        var packet = Array(repeating: UInt8(0), count: frameLength)
        packet[Offset.marker] = hostMarker
        packet[Offset.command] = command.rawValue
        packet[Offset.checksum] = checksum(packet)
        return packet
    }

    public static func makeGetLightingRequest() -> [UInt8] {
        var packet = makeSimpleCommand(.getLighting)
        packet[Offset.statePrefix] = 0x20
        packet[Offset.checksum] = checksum(packet)
        return packet
    }

    public static func parseLightingState(_ frame: [UInt8]) throws -> AtomLightingState {
        try validateResponse(frame, expectedCommand: .getLighting)

        guard let effect = LightingEffect(rawValue: frame[Offset.effect]) else {
            throw AtomProtocolError.unknownEffect(frame[Offset.effect])
        }
        guard frame[Offset.brightness] <= 100 else {
            throw AtomProtocolError.invalidBrightness(frame[Offset.brightness])
        }
        guard let speed = LightingSpeed(rawValue: frame[Offset.speed]) else {
            throw AtomProtocolError.unknownSpeed(frame[Offset.speed])
        }
        guard let direction = DirectionFlag(rawValue: frame[Offset.direction]) else {
            throw AtomProtocolError.unknownDirection(frame[Offset.direction])
        }

        return AtomLightingState(
            effect: effect,
            brightness: frame[Offset.brightness],
            speed: speed,
            direction: direction,
            colorful: frame[Offset.colorful] != 0,
            color: RGBColor(
                red: frame[Offset.red],
                green: frame[Offset.green],
                blue: frame[Offset.blue]
            ),
            rawFrame: frame
        )
    }

    public static func makeSetFrame(from state: AtomLightingState) throws -> [UInt8] {
        guard state.rawFrame.count == frameLength else {
            throw AtomProtocolError.invalidLength(state.rawFrame.count)
        }
        guard state.brightness <= 100 else {
            throw AtomProtocolError.invalidBrightness(state.brightness)
        }

        var packet = state.rawFrame
        packet[Offset.marker] = hostMarker
        packet[Offset.command] = Command.setLighting.rawValue
        packet[Offset.effect] = state.effect.rawValue
        packet[Offset.brightness] = state.brightness
        packet[Offset.speed] = state.speed.rawValue
        packet[Offset.direction] = state.direction.rawValue
        packet[Offset.colorful] = state.colorful ? 0x01 : 0x00
        packet[Offset.red] = state.color.red
        packet[Offset.green] = state.color.green
        packet[Offset.blue] = state.color.blue
        packet[Offset.checksum] = checksum(packet)
        return packet
    }

    public static func validateResponse(
        _ frame: [UInt8],
        expectedCommand: Command
    ) throws {
        guard frame.count == frameLength else {
            throw AtomProtocolError.invalidLength(frame.count)
        }
        guard frame[Offset.marker] == deviceMarker else {
            throw AtomProtocolError.invalidMarker(frame[Offset.marker])
        }
        guard frame[Offset.command] == expectedCommand.rawValue else {
            throw AtomProtocolError.unexpectedCommand(
                expected: expectedCommand.rawValue,
                actual: frame[Offset.command]
            )
        }

        let expectedChecksum = checksum(frame)
        guard frame[Offset.checksum] == expectedChecksum else {
            throw AtomProtocolError.invalidChecksum(
                expected: expectedChecksum,
                actual: frame[Offset.checksum]
            )
        }
    }

    public static func validateSetAcknowledgement(
        request: [UInt8],
        response: [UInt8]
    ) throws {
        guard request.count == frameLength else {
            throw AtomProtocolError.invalidLength(request.count)
        }
        try validateResponse(response, expectedCommand: .setLighting)

        guard Array(request[1..<frameLength]) == Array(response[1..<frameLength]) else {
            throw AtomProtocolError.setAcknowledgementMismatch
        }
    }
}

public struct RGBColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum LightingEffect: UInt8, CaseIterable, Identifiable, Sendable {
    case spectrum = 0x01
    case gradient = 0x02
    case staticRGB = 0x03
    case breathe = 0x04
    case flower = 0x05
    case wave = 0x06
    case waveUPR = 0x07
    case bubbler = 0x08
    case waveLight = 0x09
    case vortex = 0x0A
    case tide = 0x0B
    case seawave = 0x0C
    case ripple = 0x0D
    case rippleOn = 0x0E
    case single = 0x0F
    case cell = 0x10
    case knock = 0x11
    case glisten = 0x12
    case rain = 0x13
    case star = 0x14
    case firework = 0x15
    case waveBar = 0x16

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .spectrum: return "Spectrum"
        case .gradient: return "Gradient"
        case .staticRGB: return "Static"
        case .breathe: return "Breathe"
        case .flower: return "Flower"
        case .wave: return "Wave"
        case .waveUPR: return "Wave UPR"
        case .bubbler: return "Bubbler"
        case .waveLight: return "Wave Light"
        case .vortex: return "Vortex"
        case .tide: return "Tide"
        case .seawave: return "Seawave"
        case .ripple: return "Ripple"
        case .rippleOn: return "Ripple On"
        case .single: return "Single"
        case .cell: return "Cell"
        case .knock: return "Knock"
        case .glisten: return "Glisten"
        case .rain: return "Rain"
        case .star: return "Star"
        case .firework: return "Firework"
        case .waveBar: return "Wave Bar"
        }
    }

    public var idValue: UInt8 { rawValue }
}

public enum LightingSpeed: UInt8, CaseIterable, Sendable {
    case maximum = 0x00
    case fast = 0x01
    case medium = 0x02
    case slow = 0x03
    case minimum = 0x04
}

public enum DirectionFlag: UInt8, CaseIterable, Sendable {
    case normal = 0x00
    case reverse = 0x01
}

public struct AtomLightingState: Equatable, Sendable {
    public var effect: LightingEffect
    public var brightness: UInt8
    public var speed: LightingSpeed
    public var direction: DirectionFlag
    public var colorful: Bool
    public var color: RGBColor
    public var rawFrame: [UInt8]

    public init(
        effect: LightingEffect,
        brightness: UInt8,
        speed: LightingSpeed,
        direction: DirectionFlag,
        colorful: Bool,
        color: RGBColor,
        rawFrame: [UInt8]
    ) {
        self.effect = effect
        self.brightness = brightness
        self.speed = speed
        self.direction = direction
        self.colorful = colorful
        self.color = color
        self.rawFrame = rawFrame
    }
}

public enum AtomProtocolError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidLength(Int)
    case invalidMarker(UInt8)
    case unexpectedCommand(expected: UInt8, actual: UInt8)
    case invalidChecksum(expected: UInt8, actual: UInt8)
    case unknownEffect(UInt8)
    case invalidBrightness(UInt8)
    case unknownSpeed(UInt8)
    case unknownDirection(UInt8)
    case setAcknowledgementMismatch

    public var description: String {
        switch self {
        case .invalidLength(let length): return "invalid frame length: \(length), expected 64"
        case .invalidMarker(let marker): return String(format: "invalid response marker: 0x%02X", marker)
        case .unexpectedCommand(let expected, let actual):
            return String(format: "unexpected command: expected 0x%02X, got 0x%02X", expected, actual)
        case .invalidChecksum(let expected, let actual):
            return String(format: "invalid checksum: expected 0x%02X, got 0x%02X", expected, actual)
        case .unknownEffect(let value): return String(format: "unknown effect: 0x%02X", value)
        case .invalidBrightness(let value): return "invalid brightness: \(value), expected 0...100"
        case .unknownSpeed(let value): return String(format: "unknown speed: 0x%02X", value)
        case .unknownDirection(let value): return String(format: "unknown direction: 0x%02X", value)
        case .setAcknowledgementMismatch: return "SET acknowledgement does not echo the request"
        }
    }
}
