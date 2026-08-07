import AtomProtocol
import Foundation
import IOKit.hid

public enum AtomHIDTransportError: Error, CustomStringConvertible, Sendable {
    case deviceNotFound
    case openFailed(IOReturn)
    case invalidReportLength(Int)
    case writeFailed(IOReturn)
    case responseTimeout(UInt8)
    case disconnected
    case cancelled
    case busy

    public var description: String {
        switch self {
        case .deviceNotFound: return "Interface-2 RGB HID device was not found"
        case .openFailed(let result): return String(format: "IOHIDDeviceOpen failed: 0x%08X", result)
        case .invalidReportLength(let length): return "invalid HID report length: \(length)"
        case .writeFailed(let result): return String(format: "HID output report failed: 0x%08X", result)
        case .responseTimeout(let command): return String(format: "timed out waiting for response 0x%02X", command)
        case .disconnected: return "HID device disconnected"
        case .cancelled: return "HID exchange cancelled"
        case .busy: return "another HID exchange is already in flight"
        }
    }
}

public protocol AtomExchangeing: Sendable {
    func exchange(
        request: [UInt8],
        expectedCommand: AtomProtocol.Command,
        timeout: Duration
    ) async throws -> [UInt8]
}

public actor AtomHIDTransport: AtomExchangeing {
    public let deviceInfo: HIDDeviceInfo

    private let device: IOHIDDevice
    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private let dispatchQueue: DispatchQueue
    nonisolated private let logger: (@Sendable (String) -> Void)?
    private var pendingContinuation: CheckedContinuation<[UInt8], Error>?
    private var pendingCommand: AtomProtocol.Command?
    private var pendingTimeoutTask: Task<Void, Never>?
    private var isActivated = false
    private var isCancelled = false

    public static func open(
        logger: (@Sendable (String) -> Void)? = nil
    ) throws -> AtomHIDTransport {
        guard let selection = HIDDeviceEnumerator().matchingRGBDevice() else {
            throw AtomHIDTransportError.deviceNotFound
        }
        return try AtomHIDTransport(selection: selection, logger: logger)
    }

    public init(
        selection: HIDDeviceSelection,
        logger: (@Sendable (String) -> Void)? = nil
    ) throws {
        self.device = selection.device
        self.deviceInfo = selection.info
        self.inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: AtomProtocol.frameLength)
        self.dispatchQueue = DispatchQueue(label: "com.atomrgb.hid-input")
        self.logger = logger

        let openResult = IOHIDDeviceOpen(selection.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            inputBuffer.deallocate()
            throw AtomHIDTransportError.openFailed(openResult)
        }

        self.isActivated = true
        logger?(String(format: "HID open result=0x%08X interface=%@ usage=%@ inputBuffer=%d", openResult,
                      selection.info.interfaceNumber.map(String.init) ?? "-",
                      selection.info.usage.map { String(format: "0x%04X", $0) } ?? "-",
                      AtomProtocol.frameLength))

        // The dispatch queue is the modern equivalent of scheduling the
        // device on a CFRunLoop. It must be configured before registering
        // the callback and activating the device. Exchanges remain fully
        // async; callers never block this queue waiting for an ACK.
        IOHIDDeviceSetDispatchQueue(selection.device, dispatchQueue)
        logger?("input delivery configured: DispatchQueue(com.atomrgb.hid-input), CFRunLoop=none")
        IOHIDDeviceRegisterInputReportCallback(
            selection.device,
            inputBuffer,
            AtomProtocol.frameLength,
            Self.inputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        logger?("input callback registered: bufferSize=\(AtomProtocol.frameLength)")
        IOHIDDeviceSetCancelHandler(selection.device) { [weak selectionDevice = selection.device] in
            _ = selectionDevice
        }
        IOHIDDeviceActivate(selection.device)
        logger?("HID device activated; awaiting input reports")
    }

    deinit {
        if isActivated {
            IOHIDDeviceCancel(device)
        }
        _ = IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        inputBuffer.deallocate()
    }

    public func exchange(
        request: [UInt8],
        expectedCommand: AtomProtocol.Command,
        timeout: Duration = .milliseconds(500)
    ) async throws -> [UInt8] {
        guard request.count == AtomProtocol.frameLength else {
            throw AtomHIDTransportError.invalidReportLength(request.count)
        }
        guard !isCancelled else {
            throw AtomHIDTransportError.disconnected
        }
        guard pendingContinuation == nil else {
            throw AtomHIDTransportError.busy
        }

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], Error>) in
                pendingContinuation = continuation
                pendingCommand = expectedCommand
                pendingTimeoutTask?.cancel()
                pendingTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.timeoutPending(expectedCommand: expectedCommand)
                }

                do {
                    logger?("TX cmd=\(String(format: "%02X", expectedCommand.rawValue)): \(hex(request))")
                    try send(request)
                } catch {
                    pendingContinuation = nil
                    pendingCommand = nil
                    pendingTimeoutTask?.cancel()
                    pendingTimeoutTask = nil
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: {
            Task { await self.cancelPending(with: AtomHIDTransportError.cancelled) }
        })
    }

    /// Sends a validated output report without creating an ACK wait.
    ///
    /// This is intentionally separate from `exchange` for hardware
    /// diagnostics: it answers whether TX changes the keyboard even when RX
    /// delivery is unavailable. Incoming reports are still logged when a
    /// logger was supplied, but are otherwise ignored because no exchange is
    /// pending.
    public func sendWithoutResponse(_ request: [UInt8]) throws {
        guard request.count == AtomProtocol.frameLength else {
            throw AtomHIDTransportError.invalidReportLength(request.count)
        }
        guard !isCancelled else {
            throw AtomHIDTransportError.disconnected
        }
        guard pendingContinuation == nil else {
            throw AtomHIDTransportError.busy
        }

        logger?("TX raw(no ACK): \(hex(request))")
        try send(request)
    }

    public func cancel() {
        isCancelled = true
        cancelPending(with: AtomHIDTransportError.disconnected)
        if isActivated {
            IOHIDDeviceCancel(device)
            isActivated = false
        }
    }

    private func send(_ packet: [UInt8]) throws {
        let result = packet.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                0,
                buffer.baseAddress!,
                buffer.count
            )
        }
        logger?(String(format: "IOHIDDeviceSetReport result=0x%08X", result))
        guard result == kIOReturnSuccess else {
            throw AtomHIDTransportError.writeFailed(result)
        }
    }

    private func cancelPending(with error: Error) {
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingCommand = nil
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        continuation.resume(throwing: error)
    }

    private func timeoutPending(expectedCommand: AtomProtocol.Command) {
        guard pendingCommand == expectedCommand else { return }
        cancelPending(with: AtomHIDTransportError.responseTimeout(expectedCommand.rawValue))
    }

    private func handleInput(result: IOReturn, reportID: UInt32, bytes: [UInt8]) {
        logger?(String(format: "RX callback result=0x%08X reportID=%u reportLength=%d raw=%@ pending=%@",
                      result,
                      reportID,
                      bytes.count,
                      bytes.isEmpty ? "-" : hex(bytes),
                      pendingCommand.map { String(format: "%02X", $0.rawValue) } ?? "none"))

        guard result == kIOReturnSuccess else {
            cancelPending(with: AtomHIDTransportError.disconnected)
            return
        }
        guard let expectedCommand = pendingCommand,
              bytes.count == AtomProtocol.frameLength,
              bytes[0] == AtomProtocol.deviceMarker,
              bytes[1] == expectedCommand.rawValue else {
            return
        }
        guard let continuation = pendingContinuation else { return }
        pendingContinuation = nil
        pendingCommand = nil
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        logger?("RX cmd=\(String(format: "%02X", expectedCommand.rawValue)): \(hex(bytes))")
        continuation.resume(returning: bytes)
    }

    private static let inputReportCallback: IOHIDReportCallback = {
        context,
        result,
        _,
        _,
        reportID,
        report,
        reportLength in

        guard let context else { return }
        let transport = Unmanaged<AtomHIDTransport>.fromOpaque(context).takeUnretainedValue()
        let bytes: [UInt8]
        if reportLength == 0 {
            bytes = []
        } else {
            bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
        }

        let dump = bytes
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
        transport.logger?(String(format: "RAW RX result=0x%08X reportID=%u length=%d: %@",
                                 result,
                                 reportID,
                                 reportLength,
                                 dump.isEmpty ? "-" : dump))

        Task {
            await transport.handleInput(result: result, reportID: reportID, bytes: bytes)
        }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public enum AtomLightingServiceError: Error, CustomStringConvertible, Sendable {
    case noState
    case protocolError(AtomProtocolError)

    public var description: String {
        switch self {
        case .noState: return "no lighting state is available"
        case .protocolError(let error): return error.description
        }
    }
}

public actor AtomLightingService {
    public private(set) var actualState: AtomLightingState?
    public private(set) var requestedState: AtomLightingState?

    private let transport: any AtomExchangeing

    public init(transport: any AtomExchangeing) {
        self.transport = transport
    }

    public func refresh() async throws -> AtomLightingState {
        var attempt = 0
        while true {
            do {
                return try await refreshOnce()
            } catch {
                guard attempt == 0 else { throw error }
                attempt += 1
            }
        }
    }

    public func apply(
        _ mutate: @Sendable (inout AtomLightingState) -> Void
    ) async throws -> AtomLightingState {
        var attempt = 0
        while true {
            do {
                return try await applyOnce(mutate)
            } catch {
                guard attempt == 0 else { throw error }
                attempt += 1
            }
        }
    }

    private func refreshOnce() async throws -> AtomLightingState {
        _ = try await validatedExchange(.beginTransaction)
        let response = try await transport.exchange(
            request: AtomProtocol.makeGetLightingRequest(),
            expectedCommand: .getLighting,
            timeout: .milliseconds(500)
        )
        let state = try AtomProtocol.parseLightingState(response)
        _ = try await validatedExchange(.commitTransaction)
        actualState = state
        requestedState = state
        return state
    }

    private func applyOnce(
        _ mutate: @Sendable (inout AtomLightingState) -> Void
    ) async throws -> AtomLightingState {
        _ = try await validatedExchange(.beginTransaction)
        let getResponse = try await transport.exchange(
            request: AtomProtocol.makeGetLightingRequest(),
            expectedCommand: .getLighting,
            timeout: .milliseconds(500)
        )
        var state = try AtomProtocol.parseLightingState(getResponse)
        mutate(&state)
        requestedState = state

        let setRequest = try AtomProtocol.makeSetFrame(from: state)
        let setResponse = try await transport.exchange(
            request: setRequest,
            expectedCommand: .setLighting,
            timeout: .milliseconds(500)
        )
        try AtomProtocol.validateSetAcknowledgement(request: setRequest, response: setResponse)
        _ = try await validatedExchange(.commitTransaction)

        state.rawFrame = setResponse
        actualState = state
        return state
    }

    private func validatedExchange(_ command: AtomProtocol.Command) async throws -> [UInt8] {
        let response = try await transport.exchange(
            request: AtomProtocol.makeSimpleCommand(command),
            expectedCommand: command,
            timeout: .milliseconds(500)
        )
        do {
            try AtomProtocol.validateResponse(response, expectedCommand: command)
        } catch let error as AtomProtocolError {
            throw AtomLightingServiceError.protocolError(error)
        }
        return response
    }
}
