import XCTest
@testable import AtomProtocol
@testable import HIDTransport

final class AtomLightingServiceTests: XCTestCase {
    func testApplyUsesExactTransactionAndPreservesUnknownBytes() async throws {
        let transport = ScriptedTransport(state: makeStateResponse())
        let service = AtomLightingService(transport: transport)

        let result = try await service.apply { state in
            state.brightness = 24
            state.color = RGBColor(red: 0x12, green: 0x34, blue: 0x56)
        }

        let commands = await transport.commands
        XCTAssertEqual(commands, [0x01, 0x05, 0x06, 0x02])
        XCTAssertEqual(result.brightness, 24)
        XCTAssertEqual(result.color, RGBColor(red: 0x12, green: 0x34, blue: 0x56))
        XCTAssertEqual(result.rawFrame[20], 0xDE)
        XCTAssertEqual(result.rawFrame[21], 0xAD)
        XCTAssertEqual(result.rawFrame[22], 0xBE)
        XCTAssertEqual(result.rawFrame[23], 0xEF)
    }

    func testGetFailureNeverSendsSet() async throws {
        let transport = ScriptedTransport(state: makeStateResponse(), failGet: true)
        let service = AtomLightingService(transport: transport)

        do {
            _ = try await service.apply { $0.brightness = 10 }
            XCTFail("expected GET failure")
        } catch {
            let commands = await transport.commands
            XCTAssertEqual(commands, [0x01, 0x05, 0x01, 0x05])
            XCTAssertFalse(commands.contains(0x06))
        }
    }

    private func makeStateResponse() -> [UInt8] {
        var response = Array(repeating: UInt8(0), count: AtomProtocol.frameLength)
        response[0] = AtomProtocol.deviceMarker
        response[1] = AtomProtocol.Command.getLighting.rawValue
        response[4] = 0x20
        response[10] = LightingEffect.wave.rawValue
        response[11] = 50
        response[12] = LightingSpeed.medium.rawValue
        response[13] = DirectionFlag.normal.rawValue
        response[14] = 1
        response[16] = 1
        response[17] = 2
        response[18] = 3
        response[20] = 0xDE
        response[21] = 0xAD
        response[22] = 0xBE
        response[23] = 0xEF
        response[3] = AtomProtocol.checksum(response)
        return response
    }
}

private actor ScriptedTransport: AtomExchangeing {
    private let state: [UInt8]
    private let failGet: Bool
    private(set) var commands: [UInt8] = []

    init(state: [UInt8], failGet: Bool = false) {
        self.state = state
        self.failGet = failGet
    }

    func exchange(
        request: [UInt8],
        expectedCommand: AtomProtocol.Command,
        timeout: Duration
    ) async throws -> [UInt8] {
        commands.append(expectedCommand.rawValue)
        if expectedCommand == .getLighting, failGet {
            throw AtomHIDTransportError.responseTimeout(expectedCommand.rawValue)
        }

        switch expectedCommand {
        case .getLighting:
            return state
        case .beginTransaction, .commitTransaction:
            var response = request
            response[0] = AtomProtocol.deviceMarker
            response[3] = AtomProtocol.checksum(response)
            return response
        case .setLighting:
            var response = request
            response[0] = AtomProtocol.deviceMarker
            response[3] = AtomProtocol.checksum(response)
            return response
        }
    }
}
