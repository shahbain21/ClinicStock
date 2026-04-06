//
//  ClinicStockApp.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        print("Firebase connected")
        return true
    }
}

@main
struct ClinicStockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var authManager = AuthManager()
    @StateObject var inventoryManager = InventoryManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
        }
    }
}
