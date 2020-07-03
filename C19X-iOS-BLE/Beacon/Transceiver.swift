//
//  Transceiver.swift
//  C19X-iOS-BLE
//
//  Created by Freddy Choi on 03/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import os


class Transceiver: NSObject {
    private let log: OSLog
    private let peripheralManager: PeripheralManager
    private let centralManager: CentralManager

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        log = OSLog(subsystem: "Beacon", category: "Transceiver(" + identifier + ")")
        peripheralManager = PeripheralManager(identifier, serviceUUID: serviceUUID, code: code)
        centralManager = CentralManager(identifier, serviceUUIDs: [serviceUUID])
    }
}

typealias BeaconCode = Int64

class CentralManager: NSObject {
    private let log: OSLog
    private let identifier: String
    private let centralManagerDelegate: CentralManagerDelegate
    private let dispatchQueue: DispatchQueue
    private let cbCentralManager: CBCentralManager
    open override var description: String { get {
        return "<CentralManager-" + addressString + ":identifer=" + identifier + ",state=" + cbCentralManager.state.description + ">"
    }}

    init(_ identifier: String, serviceUUIDs: [CBUUID]) {
        log = OSLog(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        os_log("init", log: log, type: .debug)
        self.identifier = identifier
        self.centralManagerDelegate = CentralManagerDelegate(identifier, serviceUUIDs: serviceUUIDs)
        dispatchQueue = DispatchQueue(label: identifier)
        cbCentralManager = CBCentralManager(delegate: centralManagerDelegate, queue: dispatchQueue, options: [
            CBCentralManagerOptionRestoreIdentifierKey : identifier,
            CBCentralManagerOptionShowPowerAlertKey : true
        ])
    }
    
    deinit {
        if (cbCentralManager.state == .poweredOn) {
            cbCentralManager.stopScan()
        }
        cbCentralManager.delegate = nil
        os_log("deinit", log: log, type: .debug)
    }
    
    func scan() {
        os_log("scan ==================================================", log: log, type: .debug)
        centralManagerDelegate.centralManager(scan: cbCentralManager)
    }
}

class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let log: OSLog
    private let identifier: String
    private let serviceUUIDs: [CBUUID]
    private var cbPeripherals: Set<CBPeripheral> = []
    private var cbCentralManager: CBCentralManager?

    init(_ identifier: String, serviceUUIDs: [CBUUID]) {
        log = OSLog(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        os_log("init.delegate", log: log, type: .debug)
        self.identifier = identifier
        self.serviceUUIDs = serviceUUIDs
    }
    
    deinit {
        cbPeripherals.forEach() { peripheral in
            peripheral.delegate = nil
        }
        cbPeripherals.removeAll()
        os_log("deinit.delegate (%s)", log: log, type: .debug, identifier)
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        os_log("willRestoreState (%s)", log: log, type: .debug, central.description)
        cbCentralManager = central
        central.delegate = self
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restoredPeripherals {
                os_log("willRestoreState -> register (%s)", log: log, type: .debug, peripheral.description)
                centralManager(register: peripheral)
            }
        }
    }

    private func centralManager(register peripheral: CBPeripheral) {
        os_log("register (%s)", log: log, type: .debug, peripheral.description)
        peripheral.delegate = self
        cbPeripherals.insert(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        cbCentralManager = central
        guard central.state == .poweredOn else {
            os_log("didUpdateState (%s)", log: self.log, type: .info, central.description)
            return
        }
        os_log("didUpdateState (%s) -> scan", log: self.log, type: .debug, central.description)
        centralManager(scan: central)
    }
    
    open func centralManager(scan central: CBCentralManager) {
        guard central.state == .poweredOn else {
            os_log("scan !poweredOn (%s)", log: log, type: .fault, central.description)
            return
        }
        os_log("scan -> didDiscover", log: log, type: .debug, central.description)
        central.scanForPeripherals(withServices: serviceUUIDs)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        os_log("didDiscover (%s) -> connect", log: log, type: .debug, peripheral.description)
        centralManager(central, connect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, connect peripheral: CBPeripheral) {
        os_log("connect (%s) -> register, didConnect|didFailToConnect", log: log, type: .debug, peripheral.description)
        centralManager(register: peripheral)
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("didConnect (%s) -> didReadRSSI", log: log, type: .debug, peripheral.description)
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            os_log("didReadRSSI (%s) !error (%s)", log: log, type: .fault, peripheral.description, error.localizedDescription)
            return
        }
        let rssi = RSSI.intValue
        guard let central = cbCentralManager else {
            os_log("didReadRSSI (%s,rssi=%s) !noCentralManager", log: log, type: .fault, peripheral.description, rssi.description)
            return
        }
        os_log("didReadRSSI (%s,rssi=%s) -> disconnect", log: log, type: .debug, peripheral.description, rssi.description)
        centralManager(central, disconnect: peripheral)
    }
    
    private func centralManager(_ central: CBCentralManager, disconnect peripheral: CBPeripheral) {
        os_log("disconnect (%s) -> didDisconnectPeripheral", log: log, type: .debug, peripheral.description)
        central.cancelPeripheralConnection(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("didDisconnectPeripheral (%s) !error (%s) -> connect", log: log, type: .fault, peripheral.description, error.localizedDescription)
        } else {
            os_log("didDisconnectPeripheral (%s) -> connect", log: log, type: .debug, peripheral.description)
        }
        centralManager(central, connect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            os_log("didFailToConnect (%s) !error (%s) -> connect", log: log, type: .fault, peripheral.description, error.localizedDescription)
        } else {
            os_log("didFailToConnect (%s) -> connect", log: log, type: .debug, peripheral.description)
        }
        centralManager(central, connect: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        os_log("connectionEventDidOccur (%s,event=%s)", log: log, type: .debug, peripheral.description, event.description)
    }
}

// MARK:- PeripheralManager for advertising a beacon for detection by CentralManager

class PeripheralManager: NSObject {
    private let identifier: String
    private let peripheralManagerDelegate: PeripheralManagerDelegate
    private let log: OSLog
    private let dispatchQueue: DispatchQueue
    private let cbPeripheralManager: CBPeripheralManager
    open override var description: String { get {
        return "<PeripheralManager-" + addressString + ":identifer=" + identifier + ",state=" + cbPeripheralManager.state.description + ">"
    }}

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        log = OSLog(subsystem: "Beacon", category: "PeripheralManager(" + identifier + ")")
        os_log("init (%s)", log: log, type: .debug, identifier)
        self.identifier = identifier
        self.peripheralManagerDelegate = PeripheralManagerDelegate(identifier, serviceUUID: serviceUUID, code: code)
        dispatchQueue = DispatchQueue(label: identifier)
        cbPeripheralManager = CBPeripheralManager(delegate: peripheralManagerDelegate, queue: dispatchQueue, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey : identifier,
            CBPeripheralManagerOptionShowPowerAlertKey : true
        ])
    }
    
    deinit {
        if cbPeripheralManager.state == .poweredOn {
            cbPeripheralManager.stopAdvertising()
        }
        cbPeripheralManager.delegate = nil
        os_log("deinit (%s)", log: log, type: .debug, identifier)
    }
}

class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    private let identifier: String
    private let serviceUUID: CBUUID
    private let code: BeaconCode
    private let log: OSLog
    private var cbCentrals: Set<CBCentral> = []
    private var cbMutableService: CBMutableService?
    private var cbMutableCharacteristic: CBMutableCharacteristic?

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        log = OSLog(subsystem: "Beacon", category: "PeripheralManager(" + identifier + ")")
        os_log("init.delegate", log: log, type: .debug)
        self.identifier = identifier
        self.serviceUUID = serviceUUID
        self.code = code
    }
    
    deinit {
        cbMutableCharacteristic = nil
        cbMutableService = nil
        cbCentrals.removeAll()
        os_log("deinit.delegate", log: log, type: .debug)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        os_log("willRestoreState", log: log, type: .debug)
        peripheral.delegate = self
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services {
                if let characteristics = service.characteristics {
                    for characteristic in characteristics {
                        if characteristic.uuid.values.upper == serviceUUID.values.upper, let characteristic = characteristic as? CBMutableCharacteristic {
                            cbMutableService = service
                            cbMutableCharacteristic = characteristic
                            os_log("willRestoreState -> restored (%s,%s)", log: log, type: .debug, service.description, characteristic.description)
                        }
                    }
                }
            }
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            os_log("didUpdateState (%s)", log: log, type: .info, peripheral.description)
            return
        }
        os_log("didUpdateState (%s) -> startAdvertising", log: log, type: .debug, peripheral.description)
        peripheralManager(startAdvertising: peripheral)
    }
    
    private func peripheralManager(startAdvertising peripheral: CBPeripheralManager) {
        os_log("startAdvertising (%s) -> didStartAdvertising", log: self.log, type: .debug, peripheral.description)
        guard peripheral.state == .poweredOn else {
            return
        }
        let upper = serviceUUID.values.upper
        let beaconCharacteristicCBUUID = CBUUID(upper: upper, lower: code)
        let characteristic = CBMutableCharacteristic(type: beaconCharacteristicCBUUID, properties: [.write, .notify], value: nil, permissions: [.writeable])
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheral.stopAdvertising()
        peripheral.removeAllServices()
        peripheral.add(service)
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey : [serviceUUID]])
        cbMutableService = service
        cbMutableCharacteristic = characteristic
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            os_log("didStartAdvertising !error (%s)", log: log, type: .fault, error.localizedDescription)
            return
        }
        guard let characteristic = cbMutableCharacteristic else {
            os_log("didStartAdvertising !characteristic", log: log, type: .fault)
            return
        }
        os_log("didStartAdvertising (%s)", log: log, type: .debug, characteristic.description)
    }
}

// MARK:- Extensions

extension NSObject {
    var addressString: String { get { Unmanaged.passUnretained(self).toOpaque().debugDescription.suffix(4).description }}
}

extension CBCentralManager {
    open override var description: String { get {
        return "<CBCentralManager-" + addressString + ":state=" + state.description + ">"
    }}
}

extension CBPeripheralManager {
    open override var description: String { get {
        return "<CBPeripheralManager-" + addressString + ":state=" + state.description + ">"
    }}
}

extension CBPeripheral {
    var uuidString: String { get { identifier.uuidString }}
    open override var description: String { get {
        return "<CBPeripheral-" + addressString + ":uuid=" + uuidString + ",state=" + state.description + ">"
    }}
}

extension CBCentral {
    var uuidString: String { get { identifier.uuidString }}
    open override var description: String { get {
        return "<CBCentral-" + addressString + ":uuid=" + uuidString + ">"
    }}
}

extension CBService {
    var uuidString: String { get { uuid.uuidString }}
    open override var description: String { get {
        return "<CBService-" + addressString + ":uuid=" + uuidString + ">"
    }}
}

extension CBMutableService {
    open override var description: String { get {
        return "<CBMutableService-" + addressString + ":uuid=" + uuidString + ">"
    }}
}

extension CBMutableCharacteristic {
    var uuidString: String { get { uuid.uuidString }}
    open override var description: String { get {
        let centrals = subscribedCentrals?.description ?? "[]"
        return "<CBMutableCharacteristic-" + addressString + ":uuid=" + uuidString + ",subscribers=" + centrals + ">"
    }}
}

extension CBConnectionEvent {
    var description: String { get {
        switch self {
        case .peerConnected: return ".peerConnected"
        case .peerDisconnected: return ".peerDisconnected"
        @unknown default: return "unknown"
        }
    }}
}

extension CBManagerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .poweredOff: return ".poweredOff"
        case .poweredOn: return ".poweredOn"
        case .resetting: return ".resetting"
        case .unauthorized: return ".unauthorized"
        case .unknown: return ".unknown"
        case .unsupported: return ".unsupported"
        @unknown default: return "undefined"
        }
    }
}

extension CBPeripheralState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connected: return ".connected"
        case .connecting: return ".connecting"
        case .disconnected: return ".disconnected"
        case .disconnecting: return ".disconnecting"
        @unknown default: return "undefined"
        }
    }
}

extension CBUUID {
    /**
     Create UUID from upper and lower 64-bits values. Java long compatible conversion.
     */
    convenience init(upper: Int64, lower: Int64) {
        let upperData = (withUnsafeBytes(of: upper) { Data($0) }).reversed()
        let lowerData = (withUnsafeBytes(of: lower) { Data($0) }).reversed()
        let bytes = [UInt8](upperData) + [UInt8](lowerData)
        let data = Data(bytes)
        self.init(data: data)
    }
    
    /**
     Get upper and lower 64-bit values. Java long compatible conversion.
     */
    var values: (upper: Int64, lower: Int64) {
        let data = UUID(uuidString: self.uuidString)!.uuid
        let upperData: [UInt8] = [data.0, data.1, data.2, data.3, data.4, data.5, data.6, data.7].reversed()
        let lowerData: [UInt8] = [data.8, data.9, data.10, data.11, data.12, data.13, data.14, data.15].reversed()
        let upper = upperData.withUnsafeBytes { $0.load(as: Int64.self) }
        let lower = lowerData.withUnsafeBytes { $0.load(as: Int64.self) }
        return (upper, lower)
    }
}
