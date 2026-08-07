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
        self.registryID = registryID
        self.reportDescriptorSHA256 = reportDescriptorSHA256
    }
}

public final class HIDDeviceEnumerator {
    public init() {}

    public func enumerate(vendorID: Int, productID: Int) -> [HIDDeviceInfo] {
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
            return makeInfo(from: device, fallbackVendorID: vendorID, fallbackProductID: productID)
        }
        .sorted {
            ($0.interfaceNumber ?? Int.max, $0.usagePage ?? Int.max, $0.usage ?? Int.max)
                < ($1.interfaceNumber ?? Int.max, $1.usagePage ?? Int.max, $1.usage ?? Int.max)
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
