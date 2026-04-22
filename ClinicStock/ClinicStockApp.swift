//
//  ClinicStockApp.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  FIXES:
//  - UserManager uncommented and injected as an environment object so
//    every view shares one instance (previously UserManagementView created
//    its own private instance, which meant no cache reuse and no way for
//    other views — e.g. the dashboard — to read user/invitation state).
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

        // Configure Google Sign-In from GoogleService-Info.plist
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            print("Google Sign-In configured with client ID")
        } else {
            assertionFailure("No Google client ID found — check GoogleService-Info.plist")
        }

        return true
    }

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
    @StateObject private var userManager = UserManager()
    @StateObject private var searchService = HCPCSSearchService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
                .environmentObject(userManager)
                .environmentObject(searchService)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
