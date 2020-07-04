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
    private let logger: Logger
    private let peripheralManager: PeripheralManager
    private let centralManager: CentralManager

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "Transceiver(" + identifier + ")")
        peripheralManager = PeripheralManager(identifier, serviceUUID: serviceUUID, code: code)
        centralManager = CentralManager(identifier, serviceUUIDs: [serviceUUID])
    }
}

typealias BeaconCode = Int64

class CentralManager: NSObject {
    private let logger: Logger
    private let identifier: String
    private let centralManagerDelegate: CentralManagerDelegate
    private let dispatchQueue: DispatchQueue
    private let cbCentralManager: CBCentralManager
    open override var description: String { get {
        if #available(iOS 10.0, *) {
            return "<CentralManager-" + addressString + ":identifer=" + identifier + ",state=" + cbCentralManager.state.description + ">"
        } else {
            return "<CentralManager-" + addressString + ":identifer=" + identifier + ",state=" + String(describing: cbCentralManager.state) + ">"
        }
    }}

    init(_ identifier: String, serviceUUIDs: [CBUUID]) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        logger.log(.debug, "init")
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
        logger.log(.debug, "deinit")
    }
    
    func scan() {
        logger.log(.debug, "scan ==================================================")
        centralManagerDelegate.centralManager(scan: cbCentralManager)
    }
}

class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let logger: Logger
    private let identifier: String
    private let serviceUUIDs: [CBUUID]
    private let loopDelay = TimeInterval(2)
    private let dispatchQueue: DispatchQueue
    private var cbPeripherals: Set<CBPeripheral> = []
    private var cbCentralManager: CBCentralManager?

    init(_ identifier: String, serviceUUIDs: [CBUUID]) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        logger.log(.debug, "init.delegate")
        self.identifier = identifier
        self.serviceUUIDs = serviceUUIDs
        self.dispatchQueue = DispatchQueue(label: identifier+".delegate")
    }
    
    deinit {
        cbPeripherals.forEach() { peripheral in
            peripheral.delegate = nil
        }
        cbPeripherals.removeAll()
        logger.log(.debug, "deinit.delegate (\(identifier))")
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        logger.log(.debug, "willRestoreState (\(central.description))")
        cbCentralManager = central
        central.delegate = self
        if let restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in restoredPeripherals {
                logger.log(.debug, "willRestoreState -> register (\(peripheral.description))")
                centralManager(register: peripheral)
            }
        }
    }

    private func centralManager(register peripheral: CBPeripheral) {
        peripheral.delegate = self
        cbPeripherals.insert(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        cbCentralManager = central
        guard central.state == .poweredOn else {
            logger.log(.info, "didUpdateState (\(central.description))")
            return
        }
        logger.log(.debug, "didUpdateState (\(central.description)) -> scan")
        centralManager(scan: central)
    }
    
    open func centralManager(scan central: CBCentralManager) {
        guard central.state == .poweredOn else {
            logger.log(.fault, "scan (\(central.description)) !poweredOn")
            return
        }
        logger.log(.debug, "scan (\(central.description)) -> didDiscover")
        central.scanForPeripherals(withServices: serviceUUIDs)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.log(.debug, "didDiscover (\(peripheral.description)) -> connect")
        centralManager(central, connect: peripheral)
    }

    private func centralManager(_ central: CBCentralManager, connect peripheral: CBPeripheral) {
        self.centralManager(register: peripheral)
        guard central.state == .poweredOn else {
            self.logger.log(.fault, "connect (\(peripheral.description)) !notPoweredOn")
            return
        }
        dispatchQueue.asyncAfter(deadline: DispatchTime.now() + loopDelay) {
            self.logger.log(.debug, "connect (\(peripheral.description)) -> didConnect|didFailToConnect")
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central.state == .poweredOn else {
            logger.log(.fault, "didConnect (\(peripheral.description)) !notPoweredOn")
            return
        }
        logger.log(.debug, "didConnect (\(peripheral.description)) -> didReadRSSI")
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard !centralManager(disconnect: peripheral, on: error, from: "didReadRSSI") else {
            return
        }
        let rssi = RSSI.intValue
        logger.log(.debug, "didReadRSSI (\(peripheral.description),rssi=\(rssi.description)) -> discoverServices")
        peripheral.discoverServices(serviceUUIDs)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !centralManager(disconnect: peripheral, on: error, from: "didDiscoverServices") else {
            return
        }
        guard let service = peripheral.services?.filter({serviceUUIDs.contains($0.uuid)}).first else {
            _ = centralManager(disconnect: peripheral, on: "serviceNotFound", from: "didDiscoverServices")
            return
        }
        logger.log(.debug, "didDiscoverServices (\(peripheral.description),service=\(service.description)) -> discoverCharacteristics")
        peripheral.discoverCharacteristics(nil, for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !centralManager(disconnect: peripheral, on: error, from: "didDiscoverCharacteristicsFor") else {
            return
        }
        guard let characteristic = service.characteristics?.filter({$0.properties.contains(.notify)}).first else {
            _ = centralManager(disconnect: peripheral, on: "characteristicNotFound", from: "didDiscoverCharacteristicsFor")
            return
        }
        logger.log(.debug, "didDiscoverCharacteristicsFor (\(peripheral.description),characteristic=\(characteristic.description)) -> setNotifyValue")
        peripheral.setNotifyValue(true, for: characteristic)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard !centralManager(disconnect: peripheral, on: error, from: "didUpdateNotificationStateFor") else {
            return
        }
        logger.log(.debug, "didUpdateNotificationStateFor (\(peripheral.description),characteristic=\(characteristic.description)) -> scan, readRSSI")
        if let central = cbCentralManager {
            centralManager(scan: central)
        }
        dispatchQueue.asyncAfter(deadline: DispatchTime.now() + loopDelay) {
            peripheral.readRSSI()
        }
    }

    private func centralManager(disconnect peripheral: CBPeripheral, on error: String, from method: String) -> Bool {
        return centralManager(disconnect: peripheral, on: NSError(domain: error, code: 0, userInfo: nil), from: method)
    }
    
    private func centralManager(disconnect peripheral: CBPeripheral, on error: Error?, from method: String) -> Bool {
        guard let error = error else {
            return false
        }
        if let central = cbCentralManager {
            logger.log(.fault, "\(method) (\(peripheral.description)) !error (\(error.localizedDescription)) -> disconnect")
            centralManager(central, disconnect: peripheral)
        } else {
            logger.log(.fault, "\(method) (\(peripheral.description)) !error (\(error.localizedDescription)) !noCentralManager")
        }
        return true
    }
    
    private func centralManager(_ central: CBCentralManager, disconnect peripheral: CBPeripheral) {
        logger.log(.debug, "disconnect (\(peripheral.description)) -> didDisconnectPeripheral")
        central.cancelPeripheralConnection(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.log(.fault, "didDisconnectPeripheral (\(peripheral.description)) !error (\(error.localizedDescription)) -> connect")
        } else {
            logger.log(.debug, "didDisconnectPeripheral (\(peripheral.description)) -> connect")
        }
        centralManager(central, connect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.log(.fault, "didFailToConnect (\(peripheral.description)) !error (\(error.localizedDescription)) -> connect")
        } else {
            logger.log(.debug, "didFailToConnect (\(peripheral.description)) -> connect")
        }
        centralManager(central, connect: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        logger.log(.debug, "connectionEventDidOccur (\(peripheral.description),event=\(event.description))")
    }
}

// MARK:- PeripheralManager for advertising a beacon for detection by CentralManager

class PeripheralManager: NSObject {
    private let identifier: String
    private let peripheralManagerDelegate: PeripheralManagerDelegate
    private let logger: Logger
    private let dispatchQueue: DispatchQueue
    private let cbPeripheralManager: CBPeripheralManager
    open override var description: String { get {
        if #available(iOS 10.0, *) {
            return "<PeripheralManager-" + addressString + ":identifer=" + identifier + ",state=" + cbPeripheralManager.state.description + ">"
        } else {
            return "<PeripheralManager-" + addressString + ":identifer=" + identifier + ",state=" + String(describing: cbPeripheralManager.state) + ">"
        }
    }}

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "PeripheralManager(" + identifier + ")")
        logger.log(.debug, "init (\(identifier))")
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
        logger.log(.debug, "deinit (\(identifier))")
    }
}

class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate {
    private let identifier: String
    private let serviceUUID: CBUUID
    private let code: BeaconCode
    private let logger: Logger
    private var cbCentrals: Set<CBCentral> = []
    private var cbMutableService: CBMutableService?
    private var cbMutableCharacteristic: CBMutableCharacteristic?

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "PeripheralManager(" + identifier + ")")
        logger.log(.debug, "init.delegate")
        self.identifier = identifier
        self.serviceUUID = serviceUUID
        self.code = code
    }
    
    deinit {
        cbMutableCharacteristic = nil
        cbMutableService = nil
        cbCentrals.removeAll()
        logger.log(.debug, "deinit.delegate")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String : Any]) {
        logger.log(.debug, "willRestoreState")
        peripheral.delegate = self
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
            for service in services {
                if let characteristics = service.characteristics {
                    for characteristic in characteristics {
                        if characteristic.uuid.values.upper == serviceUUID.values.upper, let characteristic = characteristic as? CBMutableCharacteristic {
                            cbMutableService = service
                            cbMutableCharacteristic = characteristic
                            logger.log(.debug, "willRestoreState -> restored (\(service.description),\(characteristic.description))")
                        }
                    }
                }
            }
        }
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            logger.log(.info, "didUpdateState (\(peripheral.description))")
            return
        }
        logger.log(.debug, "didUpdateState (\(peripheral.description)) -> startAdvertising")
        peripheralManager(startAdvertising: peripheral)
    }
    
    private func peripheralManager(startAdvertising peripheral: CBPeripheralManager) {
        logger.log(.debug, "startAdvertising (\(peripheral.description)) -> didStartAdvertising")
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
            logger.log(.fault, "didStartAdvertising !error (\(error.localizedDescription))")
            return
        }
        guard let characteristic = cbMutableCharacteristic else {
            logger.log(.fault, "didStartAdvertising !characteristic")
            return
        }
        logger.log(.debug, "didStartAdvertising (\(characteristic.description))")
    }
}

// MARK:- Extensions

extension NSObject {
    var addressString: String { get { Unmanaged.passUnretained(self).toOpaque().debugDescription.suffix(4).description }}
}

extension CBCentralManager {
    open override var description: String { get {
        if #available(iOS 10.0, *) {
            return "<CBCentralManager-" + addressString + ":state=" + state.description + ">"
        } else {
            return "<CBCentralManager-" + addressString + ":state=" + String(describing: state) + ">"
        }
    }}
}

extension CBPeripheralManager {
    open override var description: String { get {
        if #available(iOS 10.0, *) {
            return "<CBPeripheralManager-" + addressString + ":state=" + state.description + ">"
        } else {
            return "<CBPeripheralManager-" + addressString + ":state=" + String(describing: state) + ">"
        }
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

@available(iOS 10.0, *)
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
