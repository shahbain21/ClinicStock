//
//  RootView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/6/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthManager
    
//    var body: some View {
//        Group {
//            if authManager.isLoading {
//                // Loading screen
//                VStack(spacing: 16) {
//                    Image(systemName: "cross.case.fill")
//                        .font(.system(size: 60))
//                        .foregroundColor(.blue)
//                    Text("ClinicStock")
//                        .font(.largeTitle.bold())
//                    ProgressView("Loading...")
//                }
//            } else if authManager.isAuthenticated {
//                // Logged in - show inventory
//                TestInventoryView()
//            } else {
//                // Not logged in - show login
//                TestLoginView()
//            }
//        }
        var body: some View {
            ContentView()
        }
    }

