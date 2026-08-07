import CryptoKit
import Foundation
import IOKit.hid

public struct HIDDeviceInfo: Sendable {
    public let vendorID: Int
    public let productID: Int
    public let manufacturer: String?
    public let product: String?
    public let serialNumber: String?
    public let usagePage: Int?
    public let usage: Int?
    public let interfaceNumber: Int?
    public let maxInputReportSize: Int?
    public let maxOutputReportSize: Int?
    public let maxFeatureReportSize: Int?
    public let registryID: UInt64?
    public let reportDescriptorSHA256: String?

    public init(
        vendorID: Int,
        productID: Int,
        manufacturer: String?,
        product: String?,
        serialNumber: String?,
        usagePage: Int?,
        usage: Int?,
        interfaceNumber: Int?,
        maxInputReportSize: Int?,
        maxOutputReportSize: Int?,
        maxFeatureReportSize: Int?,
        registryID: UInt64?,
        reportDescriptorSHA256: String?
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturer = manufacturer
        self.product = product
        self.serialNumber = serialNumber
        self.usagePage = usagePage
        self.usage = usage
        self.interfaceNumber = interfaceNumber
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
        self.maxFeatureReportSize = maxFeatureReportSize
        self.registryID = registryID
        self.reportDescriptorSHA256 = reportDescriptorSHA256
    }
}

public struct HIDDeviceSelection {
    public let device: IOHIDDevice
    public let info: HIDDeviceInfo

    public init(device: IOHIDDevice, info: HIDDeviceInfo) {
        self.device = device
        self.info = info
    }
}

public final class HIDDeviceEnumerator {
    public init() {}

    public func enumerate(vendorID: Int, productID: Int) -> [HIDDeviceInfo] {
        matchingDevices(vendorID: vendorID, productID: productID).map(\.info)
    }

    public func matchingRGBDevice() -> HIDDeviceSelection? {
        matchingDevices(vendorID: 0x5566, productID: 0x0008)
            .first { selection in
                guard selection.info.maxInputReportSize == 64,
                      selection.info.maxOutputReportSize == 64,
                      selection.info.product?.localizedCaseInsensitiveContains("Fantech Atom Pro") == true,
                      selection.info.usagePage == 0x0001,
                      selection.info.usage == 0x0000,
                      selection.info.reportDescriptorSHA256 == AtomInterface2Descriptor.sha256 else {
                    return false
                }

                // Some macOS IOHIDManager enumerations do not expose the USB
                // interface number. The exact descriptor fingerprint is the
                // safe fallback for that case.
                return selection.info.interfaceNumber == nil || selection.info.interfaceNumber == 2
            }
    }

    private func matchingDevices(vendorID: Int, productID: Int) -> [HIDDeviceSelection] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let copiedDevices = IOHIDManagerCopyDevices(manager) else {
            return []
        }

        let devices = copiedDevices as NSSet
        return devices.compactMap { element in
            let device = element as! IOHIDDevice
            guard let info = makeInfo(from: device, fallbackVendorID: vendorID, fallbackProductID: productID) else {
                return nil
            }
            return HIDDeviceSelection(device: device, info: info)
        }
        .sorted {
            ($0.info.interfaceNumber ?? Int.max, $0.info.usagePage ?? Int.max, $0.info.usage ?? Int.max)
                < ($1.info.interfaceNumber ?? Int.max, $1.info.usagePage ?? Int.max, $1.info.usage ?? Int.max)
        }
    }

    private func makeInfo(
        from device: IOHIDDevice,
        fallbackVendorID: Int,
        fallbackProductID: Int
    ) -> HIDDeviceInfo? {
        let vendorID = numberProperty(device, key: kIOHIDVendorIDKey) ?? fallbackVendorID
        let productID = numberProperty(device, key: kIOHIDProductIDKey) ?? fallbackProductID

        var registryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        let registryResult = IORegistryEntryGetRegistryEntryID(service, &registryID)
        let resolvedRegistryID = registryResult == KERN_SUCCESS ? registryID : nil

        let descriptorHash: String?
        if let descriptor = dataProperty(device, key: kIOHIDReportDescriptorKey) {
            descriptorHash = SHA256.hash(data: descriptor)
                .map { String(format: "%02x", $0) }
                .joined()
        } else {
            descriptorHash = nil
        }

        return HIDDeviceInfo(
            vendorID: vendorID,
            productID: productID,
            manufacturer: stringProperty(device, key: kIOHIDManufacturerKey),
            product: stringProperty(device, key: kIOHIDProductKey),
            serialNumber: stringProperty(device, key: kIOHIDSerialNumberKey),
            usagePage: numberProperty(device, key: kIOHIDPrimaryUsagePageKey),
            usage: numberProperty(device, key: kIOHIDPrimaryUsageKey),
            interfaceNumber: numberProperty(device, key: kIOHIDInterfaceIDKey),
            maxInputReportSize: numberProperty(device, key: kIOHIDMaxInputReportSizeKey),
            maxOutputReportSize: numberProperty(device, key: kIOHIDMaxOutputReportSizeKey),
            maxFeatureReportSize: numberProperty(device, key: kIOHIDMaxFeatureReportSizeKey),
            registryID: resolvedRegistryID,
            reportDescriptorSHA256: descriptorHash
        )
    }

    private func property(_ device: IOHIDDevice, key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func numberProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (property(device, key: key) as? NSNumber)?.intValue
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        property(device, key: key) as? String
    }

    private func dataProperty(_ device: IOHIDDevice, key: String) -> Data? {
        if let data = property(device, key: key) as? Data {
            return data
        }
        if let data = property(device, key: key) as? NSData {
            return Data(referencing: data)
        }
        return nil
    }
}

private enum AtomInterface2Descriptor {
    static let sha256 = "73867a68eef832176527175d6277108de35cb5ecfa6e8638966d2fb1306bd0b5"
}
