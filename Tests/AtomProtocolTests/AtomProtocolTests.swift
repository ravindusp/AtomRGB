import XCTest
@testable import AtomProtocol

final class AtomProtocolTests: XCTestCase {
    func testStaticRedFixtureChecksumAndParsing() throws {
        let frame = bytes(
            "55 06 00 6B 20 00 00 00 02 AA 03 64 01 00 00 00 " +
            "FF 00 00 00 64 04 00 CB 04 00 01 00 00 00 00 00 " +
            "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 " +
            "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        )
        let state = try AtomProtocol.parseLightingState(replacingCommandAndMarker(frame, marker: 0xAA, command: 0x05))

        XCTAssertEqual(frame.count, 64)
        XCTAssertEqual(AtomProtocol.checksum(frame), 0x6B)
        XCTAssertEqual(state.effect, .staticRGB)
        XCTAssertEqual(state.brightness, 100)
        XCTAssertEqual(state.speed, .fast)
        XCTAssertEqual(state.direction, .normal)
        XCTAssertFalse(state.colorful)
        XCTAssertEqual(state.color, RGBColor(red: 255, green: 0, blue: 0))
    }

    func testWaveBarChecksumFixtures() throws {
        let maximum = bytes(
            "55 06 00 87 20 00 00 00 02 AA 16 64 00 00 01 00 " +
            "38 E3 ED 00 64 04 00 CB 04 00 01 00 00 00 00 00 " +
            "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 " +
            "00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
        )
        let slower = maximum.withChangedByte(at: 3, to: 0x88).withChangedByte(at: 12, to: 0x01)

        XCTAssertEqual(AtomProtocol.checksum(maximum), 0x87)
        XCTAssertEqual(AtomProtocol.checksum(slower), 0x88)
    }

    func testSetBuilderPreservesUnknownBytes() throws {
        var response = Array(repeating: UInt8(0), count: 64)
        response[0] = 0xAA
        response[1] = 0x05
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

        let state = try AtomProtocol.parseLightingState(response)
        var updated = state
        updated.brightness = 24
        updated.color = RGBColor(red: 0x12, green: 0x34, blue: 0x56)

        let set = try AtomProtocol.makeSetFrame(from: updated)
        XCTAssertEqual(set[20], 0xDE)
        XCTAssertEqual(set[21], 0xAD)
        XCTAssertEqual(set[22], 0xBE)
        XCTAssertEqual(set[23], 0xEF)
        XCTAssertEqual(set[0], 0x55)
        XCTAssertEqual(set[1], 0x06)
        XCTAssertEqual(set[11], 24)
        XCTAssertEqual(Array(set[16...18]), [0x12, 0x34, 0x56])
        XCTAssertEqual(set[3], AtomProtocol.checksum(set))
    }

    func testAllEffectIDsAreCovered() {
        XCTAssertEqual(LightingEffect.allCases.count, 22)
        XCTAssertEqual(LightingEffect.allCases.map(\.rawValue), Array(UInt8(1)...UInt8(22)))
        XCTAssertEqual(LightingEffect.waveBar.displayName, "Wave Bar")
    }

    func testSimpleAndGetCommands() {
        let begin = AtomProtocol.makeSimpleCommand(.beginTransaction)
        XCTAssertEqual(begin[0], 0x55)
        XCTAssertEqual(begin[1], 0x01)
        XCTAssertEqual(begin[3], 0)

        let get = AtomProtocol.makeGetLightingRequest()
        XCTAssertEqual(get[0], 0x55)
        XCTAssertEqual(get[1], 0x05)
        XCTAssertEqual(get[4], 0x20)
        XCTAssertEqual(get[3], 0x20)
    }

    func testValidationFailures() throws {
        var frame = Array(repeating: UInt8(0), count: 64)
        frame[0] = 0xAA
        frame[1] = 0x05
        frame[3] = AtomProtocol.checksum(frame)

        XCTAssertThrowsError(try AtomProtocol.parseLightingState(Array(frame.dropLast()))) { error in
            XCTAssertEqual(error as? AtomProtocolError, .invalidLength(63))
        }

        frame[0] = 0x55
        XCTAssertThrowsError(try AtomProtocol.parseLightingState(frame)) { error in
            XCTAssertEqual(error as? AtomProtocolError, .invalidMarker(0x55))
        }

        frame[0] = 0xAA
        frame[1] = 0x06
        frame[3] = AtomProtocol.checksum(frame)
        XCTAssertThrowsError(try AtomProtocol.parseLightingState(frame)) { error in
            XCTAssertEqual(error as? AtomProtocolError, .unexpectedCommand(expected: 0x05, actual: 0x06))
        }
    }

    func testSetAcknowledgementMustEchoRequest() throws {
        let request = Array(repeating: UInt8(0x11), count: 64)
            .withChangedByte(at: 0, to: 0x55)
            .withChangedByte(at: 1, to: 0x06)
        var response = request.withChangedByte(at: 0, to: 0xAA)
        response[3] = AtomProtocol.checksum(response)

        XCTAssertNoThrow(try AtomProtocol.validateSetAcknowledgement(request: request, response: response))
        XCTAssertThrowsError(
            try AtomProtocol.validateSetAcknowledgement(
                request: request,
                response: response.withChangedByte(at: 20, to: 0x22)
            )
        )
    }

    private func bytes(_ value: String) -> [UInt8] {
        value.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    private func replacingCommandAndMarker(_ frame: [UInt8], marker: UInt8, command: UInt8) -> [UInt8] {
        frame.withChangedByte(at: 0, to: marker).withChangedByte(at: 1, to: command)
            .withRecalculatedChecksum()
    }
}

private extension Array where Element == UInt8 {
    func withChangedByte(at index: Int, to value: UInt8) -> [UInt8] {
        var copy = self
        copy[index] = value
        return copy
    }

    func withRecalculatedChecksum() -> [UInt8] {
        var copy = self
        copy[3] = AtomProtocol.checksum(copy)
        return copy
    }
}
