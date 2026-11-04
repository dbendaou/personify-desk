import Foundation

/// Bluetooth SIG assigned numbers used to label explorer rows.
///
/// A match means the UUID is the SIG's published identifier for that name.
/// It does not mean a Distech or nLight device implements the profile.
public enum AssignedNumbers {
    public static func serviceName(uuid: String) -> String? {
        services[bluetoothAlias(uuid)]
    }

    public static func characteristicName(uuid: String) -> String? {
        characteristics[bluetoothAlias(uuid)]
    }

    public static func descriptorName(uuid: String) -> String? {
        descriptors[bluetoothAlias(uuid)]
    }

    /// Bluetooth SIG company identifiers. These label manufacturer data.
    /// None of them is published as Distech's or Acuity's identifier.
    public static func companyName(_ companyID: UInt16) -> String? {
        companies[companyID]
    }

    private static let services: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "180A": "Device Information",
        "180F": "Battery",
        "181A": "Environmental Sensing",
    ]

    private static let characteristics: [String: String] = [
        "2A00": "Device Name",
        "2A01": "Appearance",
        "2A04": "Peripheral Preferred Connection Parameters",
        "2A05": "Service Changed",
        "2A19": "Battery Level",
        "2A23": "System ID",
        "2A24": "Model Number String",
        "2A25": "Serial Number String",
        "2A26": "Firmware Revision String",
        "2A27": "Hardware Revision String",
        "2A28": "Software Revision String",
        "2A29": "Manufacturer Name String",
        "2A2A": "IEEE 11073-20601 Regulatory Certification Data List",
        "2A50": "PnP ID",
        "2A6D": "Pressure",
        "2A6E": "Temperature",
        "2A6F": "Humidity",
        "2AFB": "Illuminance",
    ]

    private static let descriptors: [String: String] = [
        "2901": "Characteristic User Description",
        "2902": "Client Characteristic Configuration",
        "2904": "Characteristic Presentation Format",
    ]

    private static let companies: [UInt16: String] = [
        0x0006: "Microsoft",
        0x004C: "Apple, Inc.",
        0x0059: "Nordic Semiconductor",
        0x00E0: "Google",
    ]
}
