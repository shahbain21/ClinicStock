//
//  ClinicStockApp.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  UPDATED:
//  - Added Google Sign-In support
//  - Added UserManager
//  - Added HCPCSSearchService
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        print("Firebase connected")
        return true
    }

    // Handle Google Sign-In redirect URL
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct ClinicStockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var authManager = AuthManager()
    @StateObject private var inventoryManager = InventoryManager()
    //@StateObject private var userManager = UserManager()
    @StateObject private var searchService = HCPCSSearchService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
                //.environmentObject(userManager)
                .environmentObject(searchService)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
