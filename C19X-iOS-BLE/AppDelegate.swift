//
//  AppDelegate.swift
//  C19X-iOS-BLE
//
//  Created by Freddy Choi on 03/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import UIKit
import CoreBluetooth

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let logger: Logger = ConcreteLogger(subsystem: "App", category: "AppDelegate")
    // BLE service UUID
    private let beaconServiceCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")
    // BLE beacon device ID
    private let beaconCode = BeaconCode(1)
    // BLE transmitter + receiver for devices to detect each other
    private var transceiver: Transceiver?
    private var database: Database?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logger.log(.debug, "didFinishLaunchingWithOptions")
        if #available(iOS 10.0, *) {
            database = ConcreteDatabase()
        } else {
            database = MockDatabase()
        }
        database?.insert("applicationDidFinishLaunchingWithOptions")
        // Initialise BLE transmitter + receiver, change beacon code to distinguish devices
        transceiver = Transceiver("c19x", serviceUUID: beaconServiceCBUUID, code: beaconCode, database: database!)
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        database?.insert("applicationWillEnterForeground")
        database?.export()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        database?.insert("applicationDidEnterBackground")
    }
}

