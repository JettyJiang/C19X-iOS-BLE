//
//  Logger.swift
//  C19X-iOS-BLE
//
//  Created by Freddy Choi on 04/07/2020.
//  Copyright © 2020 C19X. All rights reserved.
//

import Foundation
import os

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
    private let log: OSLog?
    
    required init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        if #available(iOS 10.0, *) {
            log = OSLog(subsystem: subsystem, category: category)
        } else {
            log = nil
        }
    }

    func log(_ level: LogLevel, _ message: String) {
        guard let log = log else {
            let entry = Date().description + " [" + subsystem + "] [" + category + "] : " + message
            print(entry)
            return
        }
        if #available(iOS 10.0, *) {
            switch (level) {
            case .debug:
                os_log("%s", log: log, type: .debug, message)
            case .info:
                os_log("%s", log: log, type: .info, message)
            case .fault:
                os_log("%s", log: log, type: .fault, message)
            }
            return
        }
    }
}
