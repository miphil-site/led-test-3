import Foundation
import CoreBluetooth
import Combine

struct GoveeDevice: Identifiable {
    let id: String          // advertised name, z.B. "Govee_H6125_294D"
    let displayName: String // z.B. "H6125"
    var peripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var status: String = "Suche ..."
    var isConnected: Bool = false
    var isOn: Bool = true
    var brightness: Double = 100
}

// Govee BLE-Protokoll: 20-Byte-Pakete mit XOR-Checksumme.
// Gleiche Logik wie im Python-Script (govee_ble_control.py).
enum GoveePacket {
    static let writeCharUUID = CBUUID(string: "00010203-0405-0607-0809-0a0b0c0d2b11")

    static func build(cmd: UInt8, payload: [UInt8]) -> Data {
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0x33
        frame[1] = cmd
        for (i, b) in payload.enumerated() where i + 2 < 19 {
            frame[2 + i] = b
        }
        var checksum: UInt8 = 0
        for b in frame[0..<19] { checksum ^= b }
        frame[19] = checksum
        return Data(frame)
    }

    static func power(_ on: Bool) -> Data {
        build(cmd: 0x01, payload: [on ? 0x01 : 0x00])
    }

    static func brightness(_ percent: Int) -> Data {
        let clamped = max(0, min(100, percent))
        let value = UInt8(round(Double(clamped) * 255.0 / 100.0))
        return build(cmd: 0x04, payload: [value])
    }
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published var devices: [GoveeDevice] = [
        GoveeDevice(id: "Govee_H6125_294D", displayName: "H6125"),
        GoveeDevice(id: "Govee_H612F_101E", displayName: "H612F"),
    ]

    private var central: CBCentralManager!
    private var peripherals: [String: CBPeripheral] = [:]  // name -> peripheral

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    private func index(forName name: String) -> Int? {
        devices.firstIndex(where: { $0.id == name })
    }

    private func startScanIfPoweredOn() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    func setPower(name: String, on: Bool) {
        guard let idx = index(forName: name) else { return }
        devices[idx].isOn = on
        sendIfReady(name: name, data: GoveePacket.power(on))
    }

    func setBrightness(name: String, percent: Double) {
        guard let idx = index(forName: name) else { return }
        devices[idx].brightness = percent
        sendIfReady(name: name, data: GoveePacket.brightness(Int(percent)))
    }

    func setAllPower(on: Bool) {
        for device in devices {
            setPower(name: device.id, on: on)
        }
    }

    private func sendIfReady(name: String, data: Data) {
        guard let idx = index(forName: name),
              let peripheral = devices[idx].peripheral,
              let char = devices[idx].writeCharacteristic,
              peripheral.state == .connected else {
            return
        }
        peripheral.writeValue(data, for: char, type: .withoutResponse)
    }

    private func updateStatus(name: String, text: String, connected: Bool) {
        guard let idx = index(forName: name) else { return }
        devices[idx].status = text
        devices[idx].isConnected = connected
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanIfPoweredOn()
        } else {
            for device in devices {
                updateStatus(name: device.id, text: "Bluetooth aus", connected: false)
            }
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        guard let name = peripheral.name, index(forName: name) != nil else { return }
        guard peripherals[name] == nil else { return }

        peripherals[name] = peripheral
        updateStatus(name: name, text: "Verbinde ...", connected: false)
        peripheral.delegate = self
        central.connect(peripheral, options: nil)

        if let idx = index(forName: name) {
            devices[idx].peripheral = peripheral
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let name = peripheral.name else { return }
        updateStatus(name: name, text: "Fehler: \(error?.localizedDescription ?? "?")", connected: false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let name = peripheral.name else { return }
        updateStatus(name: name, text: "Getrennt", connected: false)
        peripherals[name] = nil
        // erneut versuchen, in Reichweite wieder zu finden
        startScanIfPoweredOn()
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let name = peripheral.name, let idx = index(forName: name) else { return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == GoveePacket.writeCharUUID {
                devices[idx].writeCharacteristic = characteristic
                updateStatus(name: name, text: "Verbunden", connected: true)
                // aktuellen Zustand direkt senden
                sendIfReady(name: name, data: GoveePacket.power(devices[idx].isOn))
                sendIfReady(name: name, data: GoveePacket.brightness(Int(devices[idx].brightness)))
            }
        }
    }
}
