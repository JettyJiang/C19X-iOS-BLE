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
    // BLE service UUID
    private let beaconServiceCBUUID = CBUUID(string: "0022D481-83FE-1F13-0000-000000000000")
    // BLE beacon device ID
    private let beaconCode = BeaconCode(1)
    // BLE transmitter + receiver for devices to detect each other
    private var transceiver: Transceiver?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialise BLE transmitter + receiver, change beacon code to distinguish devices
        transceiver = Transceiver("c19x", serviceUUID: beaconServiceCBUUID, code: beaconCode)
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

