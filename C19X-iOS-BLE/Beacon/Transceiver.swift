//
//  Transceiver.swift
//  C19X-iOS-BLE
//
//  Created by Freddy Choi on 03/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import CoreBluetooth
import CoreLocation
import UIKit
import os


class Transceiver: NSObject, CLLocationManagerDelegate {
    private let logger: Logger
    private let peripheralManager: PeripheralManager
    private let centralManager: CentralManager
    private let locationManager: LocationManager
    private let notificationManager: NotificationManager

    init(_ identifier: String, serviceUUID: CBUUID, code: BeaconCode, database: Database) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "Transceiver(" + identifier + ")")
        peripheralManager = PeripheralManager(identifier, serviceUUID: serviceUUID, code: code)
        centralManager = CentralManager(identifier, serviceUUIDs: [serviceUUID], database: database)
        locationManager = LocationManager()
        notificationManager = NotificationManager(identifier)
        notificationManager.notification("C19X-iOS-BLE", "Active", delay: 180, repeats: true)
    }
}

typealias BeaconCode = Int64

class LocationManager: NSObject, CLLocationManagerDelegate {
    private let logger: Logger
    private let locationManager = CLLocationManager()
    private let uuid = UUID(uuidString: "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6")!
    
    override init() {
        logger = ConcreteLogger(subsystem: "Beacon", category: "LocationManager")
        logger.log(.debug, "init")
        super.init()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization()
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 3000.0
        if #available(iOS 9.0, *) {
          locationManager.allowsBackgroundLocationUpdates = true
        }
        locationManager.startUpdatingLocation()
        if #available(iOS 13.0, *) {
            locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        } else {
            locationManager.startRangingBeacons(in: CLBeaconRegion(proximityUUID: uuid, identifier: "iBeacon"))
        }
    }
    
    deinit {
        if #available(iOS 13.0, *) {
            locationManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: uuid))
        } else {
            locationManager.stopRangingBeacons(in: CLBeaconRegion(proximityUUID: uuid, identifier: "iBeacon"))
        }
        locationManager.stopUpdatingLocation()
        logger.log(.debug, "deinit")
    }
}

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let logger: Logger
    private let identifier: String
    
    init(_ identifier: String) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "NotificationManager(" + identifier + ")")
        self.identifier = identifier
    }

    func notification(_ title: String, _ body: String, delay: TimeInterval, repeats: Bool) {
        if #available(iOS 10.0, *) {
            notification10(title, body, delay: delay, repeats: repeats)
        }
    }
    
    @available(iOS 10.0, *)
    private func notification10(_ title: String, _ body: String, delay: TimeInterval, repeats: Bool) {
        DispatchQueue.main.async {
            // Request authorisation for notification
            let center = UNUserNotificationCenter.current()
            center.requestAuthorization(options: [.alert]) { granted, error in
                if let error = error {
                    self.logger.log(.fault, "notification denied, authorisation failed (error=\(error.localizedDescription))")
                } else if granted {
                    let identifier = "C19X-iOS-BLE.notification"
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = UNNotificationSound.default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: repeats)
                    center.removePendingNotificationRequests(withIdentifiers: [identifier])
                    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                    center.add(request)
                    self.logger.log(.debug, "notification (title=\(title),message=\(body))")
                } else {
                    self.logger.log(.fault, "notification denied, authorisation denied")
                }
            }
        }
    }
}

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

    init(_ identifier: String, serviceUUIDs: [CBUUID], database: Database) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        logger.log(.debug, "init")
        self.identifier = identifier
        self.centralManagerDelegate = CentralManagerDelegate(identifier, serviceUUIDs: serviceUUIDs, database: database)
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
}

class CentralManagerDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let logger: Logger
    private let identifier: String
    private let serviceUUIDs: [CBUUID]
    private let database: Database
    private let loopDelay = TimeInterval(2)
    private let dispatchQueue: DispatchQueue
    private var cbPeripherals: Set<CBPeripheral> = []
    private var cbCentralManager: CBCentralManager?

    init(_ identifier: String, serviceUUIDs: [CBUUID], database: Database) {
        logger = ConcreteLogger(subsystem: "Beacon", category: "CentralManager(" + identifier + ")")
        logger.log(.debug, "init.delegate")
        self.identifier = identifier
        self.serviceUUIDs = serviceUUIDs
        self.database = database
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
        logger.log(.debug, "register (\(peripheral.description))")
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
            logger.log(.fault, "scan !poweredOn (\(central.description))")
            return
        }
        logger.log(.debug, "scan (\(central.description)) -> didDiscover")
        database.insert("scan")
        central.scanForPeripherals(withServices: serviceUUIDs)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        logger.log(.debug, "didDiscover (\(peripheral.description)) -> connect")
        database.insert("didDiscover  (\(peripheral.description))")
        centralManager(central, connect: peripheral)
    }

    private func centralManager(_ central: CBCentralManager, connect peripheral: CBPeripheral) {
        logger.log(.debug, "connect (\(peripheral.description)) -> register, didConnect|didFailToConnect")
        centralManager(register: peripheral)
        dispatchQueue.asyncAfter(deadline: DispatchTime.now() + loopDelay) {
            central.connect(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.log(.debug, "didConnect (\(peripheral.description)) -> didReadRSSI")
        peripheral.readRSSI()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            logger.log(.fault, "didReadRSSI (\(peripheral.description)) !error (\(error.localizedDescription))")
            return
        }
        let rssi = RSSI.intValue
        guard let central = cbCentralManager else {
            logger.log(.fault, "didReadRSSI (\(peripheral.description),rssi=\(rssi.description)) !noCentralManager")
            return
        }
        logger.log(.debug, "didReadRSSI (\(peripheral.description),rssi=\(rssi.description)) -> disconnect")
        database.insert("didReadRSSI (\(peripheral.description),rssi=\(rssi.description))")
        centralManager(central, disconnect: peripheral)
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
        database.insert("didDisconnectPeripheral  (\(peripheral.description))")
        centralManager(central, connect: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            logger.log(.fault, "didFailToConnect (\(peripheral.description)) !error (\(error.localizedDescription)) -> connect")
        } else {
            logger.log(.debug, "didFailToConnect (\(peripheral.description)) -> connect")
        }
        database.insert("didFailToConnect  (\(peripheral.description))")
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
