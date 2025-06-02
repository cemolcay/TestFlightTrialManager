//
//  AppDelegate.swift
//  TestFlightTrialManager
//
//  Created by Cem Olcay on 6/2/25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configure trial manager
        TestFlightTrialManager.configure(with: .init(
            trialDuration: 1 * 60,      // 1 minute
            password: "pass",           // Password for invited beta users
            userDefaultsSuiteName: nil, // Optional custom UserDefaults suite
            simulationMode: true        // simulate testflight for developemnt
        ))
        
        // For development reset trial on start
        TestFlightTrialManager.shared.lockTrial()
        TestFlightTrialManager.shared.resetTrialTime()
        TestFlightTrialManager.shared.startTrialIfNeeded()
        
        return true
    }
}

