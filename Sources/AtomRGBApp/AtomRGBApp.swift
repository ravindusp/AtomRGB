import AtomProtocol
import struct AtomProtocol.RGBColor
import AppKit
import HIDTransport
import SwiftUI

@main
struct AtomRGBApp: App {
    @StateObject private var model = AtomLightingViewModel()

    var body: some Scene {
        WindowGroup {
            LightingView(model: model)
                .frame(minWidth: 440, minHeight: 560)
                .task {
                    await model.start()
                }
                .onDisappear {
                    Task {
                        await model.stop()
                    }
                }
        }
    }
}

@MainActor
final class AtomLightingViewModel: ObservableObject {
    @Published var effect: LightingEffect = .staticRGB
    @Published var brightness: Double = 100
    @Published var speed: LightingSpeed = .medium
    @Published var direction: DirectionFlag = .normal
    @Published var colorful = false
    @Published var color = Color.red
    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Disconnected"
    @Published private(set) var errorMessage: String?

    private var transport: AtomHIDTransport?
    private var service: AtomLightingService?
    private var lastSyncedState: AtomLightingState?
    private var monitorTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    var supportsColorControls: Bool {
        ![.flower, .cell].contains(effect)
    }

    var supportsDirection: Bool {
        [.wave, .waveUPR, .bubbler, .waveLight, .vortex, .seawave].contains(effect)
    }

    var directionLabels: (normal: String, reverse: String) {
        switch effect {
        case .wave, .vortex:
            return ("Right", "Left")
        case .waveUPR, .bubbler, .waveLight, .seawave:
            return ("Down", "Up")
        default:
            return ("Normal", "Reverse")
        }
    }

    func start() async {
        guard monitorTask == nil else { return }
        monitorTask = Task { @MainActor [weak self] in
            await self?.connect()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                if self.isConnected {
                    if HIDDeviceEnumerator().matchingRGBDevice() == nil {
                        await self.disconnectForMonitor()
                    }
                } else {
                    await self.connect()
                }
            }
        }
    }

    func stop() async {
        monitorTask?.cancel()
        monitorTask = nil
        debounceTask?.cancel()
        await disconnectForMonitor()
    }

    func connect() async {
        guard !isBusy, !isConnected else { return }
        isBusy = true
        errorMessage = nil
        status = "Connecting…"

        do {
            let transport = try AtomHIDTransport.open()
            let service = AtomLightingService(transport: transport)
            let state = try await service.refresh()
            self.transport = transport
            self.service = service
            apply(state)
            isConnected = true
            status = "Connected"
        } catch {
            isConnected = false
            status = "Disconnected"
            errorMessage = error.localizedDescription
        }

        isBusy = false
    }

    func refresh() {
        guard let service, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            do {
                let state = try await service.refresh()
                self?.apply(state)
                self?.status = "Connected"
            } catch {
                self?.handle(error)
            }
            self?.isBusy = false
        }
    }

    func effectChanged() {
        guard effect != lastSyncedState?.effect else { return }
        performMutation { [effect] state in
            state.effect = effect
        }
    }

    func speedChanged() {
        guard speed != lastSyncedState?.speed else { return }
        performMutation { [speed] state in
            state.speed = speed
        }
    }

    func directionChanged() {
        guard direction != lastSyncedState?.direction else { return }
        performMutation { [direction] state in
            state.direction = direction
        }
    }

    func colorfulChanged() {
        guard colorful != lastSyncedState?.colorful else { return }
        performMutation { [colorful] state in
            state.colorful = colorful
        }
    }

    func brightnessChanged() {
        let value = UInt8(max(0, min(100, Int(brightness.rounded()))))
        guard value != lastSyncedState?.brightness else { return }
        scheduleDebouncedMutation { [brightness] state in
            state.brightness = UInt8(max(0, min(100, Int(brightness.rounded()))))
        }
    }

    func colorChanged() {
        guard let rgb = rgbColor(from: color) else { return }
        guard rgb != lastSyncedState?.color else { return }
        scheduleDebouncedMutation { [rgb] state in
            state.color = rgb
        }
    }

    private func performMutation(
        _ mutation: @escaping @Sendable (inout AtomLightingState) -> Void
    ) {
        guard let service, isConnected else { return }
        isBusy = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            do {
                let state = try await service.apply(mutation)
                self?.apply(state)
                self?.status = "Connected"
            } catch {
                self?.handle(error)
            }
            self?.isBusy = false
        }
    }

    private func scheduleDebouncedMutation(
        _ mutation: @escaping @Sendable (inout AtomLightingState) -> Void
    ) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            self?.performMutation(mutation)
        }
    }

    private func apply(_ state: AtomLightingState) {
        lastSyncedState = state
        effect = state.effect
        brightness = Double(state.brightness)
        speed = state.speed
        direction = state.direction
        colorful = state.colorful
        color = Color(
            red: Double(state.color.red) / 255,
            green: Double(state.color.green) / 255,
            blue: Double(state.color.blue) / 255
        )
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
        if error is AtomHIDTransportError {
            status = "Disconnected"
            isConnected = false
            Task { @MainActor [weak self] in
                await self?.disconnectForMonitor()
            }
        } else {
            status = "Error"
        }
    }

    private func disconnectForMonitor() async {
        if let transport {
            await transport.cancel()
        }
        transport = nil
        service = nil
        lastSyncedState = nil
        isConnected = false
        status = "Disconnected"
    }

    private func rgbColor(from color: Color) -> RGBColor? {
        guard let cgColor = color.cgColor,
              let converted = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB) else {
            return nil
        }
        return RGBColor(
            red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded()))
        )
    }
}

struct LightingView: View {
    @ObservedObject var model: AtomLightingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            GroupBox("Lighting") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Effect", selection: $model.effect) {
                        ForEach(LightingEffect.allCases) { effect in
                            Text(effect.displayName).tag(effect)
                        }
                    }
                    .onChange(of: model.effect) { _ in model.effectChanged() }

                    HStack {
                        Text("Brightness")
                        Slider(value: $model.brightness, in: 0...100, step: 1)
                            .onChange(of: model.brightness) { _ in model.brightnessChanged() }
                        Text("\(Int(model.brightness))%")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }

                    Picker("Speed", selection: $model.speed) {
                        Text("Maximum").tag(LightingSpeed.maximum)
                        Text("Fast").tag(LightingSpeed.fast)
                        Text("Medium").tag(LightingSpeed.medium)
                        Text("Slow").tag(LightingSpeed.slow)
                        Text("Minimum").tag(LightingSpeed.minimum)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.speed) { _ in model.speedChanged() }

                    if model.supportsColorControls {
                        HStack {
                            ColorPicker("Color", selection: $model.color, supportsOpacity: false)
                                .onChange(of: model.color) { _ in model.colorChanged() }
                            Toggle("Colorful", isOn: $model.colorful)
                                .onChange(of: model.colorful) { _ in model.colorfulChanged() }
                        }
                    }

                    if model.supportsDirection {
                        Picker("Direction", selection: $model.direction) {
                            Text(model.directionLabels.normal).tag(DirectionFlag.normal)
                            Text(model.directionLabels.reverse).tag(DirectionFlag.reverse)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: model.direction) { _ in model.directionChanged() }
                    }
                }
                .disabled(!model.isConnected || model.isBusy)
            }

            HStack {
                Button("Refresh") { model.refresh() }
                    .disabled(!model.isConnected || model.isBusy)
                Spacer()
                if model.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AtomRGB")
                    .font(.largeTitle.weight(.semibold))
                Text("Fantech Atom Pro 63 / MK912")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(model.status, systemImage: model.isConnected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(model.isConnected ? .green : .secondary)
        }
    }
}
