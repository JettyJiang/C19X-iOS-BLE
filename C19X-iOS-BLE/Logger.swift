//
//  Logger.swift
//  C19X-iOS-BLE
//
//  Created by Freddy Choi on 04/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation

protocol Logger {
    init(subsystem: String, category: String)
    
    func log(_ level: LogLevel, _ message: String)
}

enum LogLevel: String {
    case debug, info, fault
}

class ConcreteLogger: NSObject, Logger {
    private let subsystem: String
    private let category: String
    
    required init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    func log(_ level: LogLevel, _ message: String) {
        print(Date().description + " [" + subsystem + "] [" + category + "] : " + message)
    }
}
