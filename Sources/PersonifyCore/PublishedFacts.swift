import Foundation

/// Statements taken from public Distech, Acuity, and Bluetooth documents.
/// Wire encodings for room commands are intentionally absent.
public enum PublishedFacts {
    public static let commissioning =
        "Distech's ECLYPSE REST resource ble-room-devices documents bluetoothMode 0 Disabled, 1 Open (no PIN), 2 Commissioning (factory default PIN 999995, short range), and 3 Private (a six-digit PIN, and the factory default is not allowed)."

    public static let facilitiesFourAndSix =
        "ECLYPSE Facilities 2.5.0 describes those same four modes. On that page the Bluetooth Pin Code parameter is called a 4-digit field, while Private mode is described as six digits."

    public static let nLightPINs =
        "The nLight UNITOUCH manual says every PIN on that product is 6 digits, including the Bluetooth PIN created for my PERSONIFY. That Bluetooth PIN is separate from the administrator PIN. Bluetooth on the wall unit is disabled while an administrator is logged in."

    public static let pairingFootnote =
        "Distech publishes 999995 as the commissioning default. Private mode on that API uses some other six-digit code. This field submits the digits you leave in it, at any length up to the 16-octet Bluetooth PIN."

    public static let noGATT =
        "No public GATT service list or command encoding was found for my PERSONIFY, the ECLYPSE Sky SDK, Allure UNITOUCH, EC-Multi-Sensor-BLE, nLight UNITOUCH, or the ECLYPSE Connected Thermostat (ECY-STAT). The Sky SDK Getting Started page is a documentation-portal shell and does not print those UUIDs. The SDK download sits behind Distech's developer-portal agreement."

    public static let allureControls =
        "The Allure UNITOUCH user guide shows a temperature slider (absolute setpoint or a relative offset, chosen in EC-gfxProgram), heating/cooling mode, a fan slider in Level or Analog mode, and an Auto control that turns off when the slider moves. The spec sheet lists up to 8 lighting groups and 8 sunblind groups. The temperature sensor range is 0–50 °C. Humidity and CO2 appear on equipped models."

    public static let nLightControls =
        "The nLight UNITOUCH manual describes up to 16 switch channels, typed Light, CCT, Shade, or None, plus up to 16 scenes. Light channels have on/off (on restores the previous dim level) and raise/lower. Shade channels have a position. It also has up to 16 occupancy channels and 16 photocell channels."

    public static let sensorHardware =
        "EC-Multi-Sensor-BLE combines a motion detector, a light sensor, a temperature sensor, a BLE transceiver, and what Distech calls open beacon technology. ECY-STAT's spec sheet lists Bluetooth 4.2 for my PERSONIFY, alongside Wi-Fi and IP."

    public static let beaconUUID =
        "The ble-room-devices resource has a uuid property described as the beacon-network UUID. The published example is not a well-formed 32-digit UUID. iBeacon advertisements use Apple's public layout and can be compared with that property after a capture. The comparison is not verified."

    public static let lengthHint =
        "Six digits is the length Distech's current private-mode text and the nLight manual describe. One facilities release also calls the Bluetooth pin field 4 digits. Other lengths are still accepted."

    public static let sources: [String] = [
        "https://wiki.distech-controls.com/RestAPI/Engine/Resources/BLE-Room-Devices/ResourceIndex/GET-resourceIndex",
        "https://docs.distech-controls.com/bundle/ECLYPSE-BI-UG-v250/page/en-US/1002190475.html",
        "https://docs.distech-controls.com/bundle/ECLYPSE-Sky-SDK_GS/resource/ECLYPSE%20Sky%20SDK_GS.pdf",
        "https://developer.distech-controls.com/about",
        "https://www.acuitybrands.com/products/detail/947818/distech-controls/my-personify-mobile-app",
        "https://img.acuitybrands.com/public-assets/catalog/981468/nlight-unitouch-manual-3-0.pdf",
    ]
}
