import Foundation
import HIDTransport

private let defaultVendorID = 0x5566
private let defaultProductID = 0x0008

private func parseInteger(_ value: String) -> Int? {
    if value.lowercased().hasPrefix("0x") {
        return Int(value.dropFirst(2), radix: 16)
    }
    return Int(value)
}

private func printUsage() {
    print("Usage: atomctl info [--vid 0x5566] [--pid 0x0008]")
    print("\nRead-only HID enumeration. No reports are opened or sent.")
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "info" else {
    printUsage()
    exit(arguments.isEmpty ? 0 : 64)
}

var vendorID = defaultVendorID
var productID = defaultProductID
var index = 1

while index < arguments.count {
    switch arguments[index] {
    case "--vid":
        guard index + 1 < arguments.count, let value = parseInteger(arguments[index + 1]) else {
            fputs("Invalid --vid value.\n", stderr)
            exit(64)
        }
        vendorID = value
        index += 2
    case "--pid":
        guard index + 1 < arguments.count, let value = parseInteger(arguments[index + 1]) else {
            fputs("Invalid --pid value.\n", stderr)
            exit(64)
        }
        productID = value
        index += 2
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        fputs("Unknown argument: \(arguments[index])\n", stderr)
        exit(64)
    }
}

let devices = HIDDeviceEnumerator().enumerate(vendorID: vendorID, productID: productID)
if devices.isEmpty {
    print(String(format: "No HID collections found for VID 0x%04X PID 0x%04X.", vendorID, productID))
    exit(1)
}

print(String(format: "Found %d HID collection(s) for VID 0x%04X PID 0x%04X", devices.count, vendorID, productID))
for (index, device) in devices.enumerated() {
    print("\nCollection \(index + 1)")
    print(String(format: "  VID/PID:       0x%04X:0x%04X", device.vendorID, device.productID))
    print("  Manufacturer:  \(device.manufacturer ?? "-")")
    print("  Product:       \(device.product ?? "-")")
    print("  Serial:        \(device.serialNumber ?? "-")")
    if let usagePage = device.usagePage, let usage = device.usage {
        print(String(format: "  Usage:         0x%04X / 0x%04X", usagePage, usage))
    } else {
        print("  Usage:         -")
    }
    print("  Interface:     \(device.interfaceNumber.map(String.init) ?? "-")")
    print(String(format: "  Registry ID:   %@", device.registryID.map { String($0) } ?? "-"))
    print("  Descriptor SHA: \(device.reportDescriptorSHA256 ?? "-")")
}
