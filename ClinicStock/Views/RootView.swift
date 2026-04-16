//
//  RootView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  FIXED:
//  - Uses .onChange to watch for currentUser being set
//  - Starts listening as soon as clinicID is available
//  - Stops listening on sign out
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        Group {
            if authManager.isLoading {
                SplashView()

            } else if authManager.isAuthenticated {
                MainTabView()

            } else {
                LoginView()
            }
        }
        // ── Start listening when user is loaded ──
        .onChange(of: authManager.currentUser?.clinicID) { _, clinicID in
            if let clinicID = clinicID, !clinicID.isEmpty {
                print("Starting inventory listener for clinic: \(clinicID)")
                inventoryManager.startListening(clinicID: clinicID)
            }
        }
        // ── Stop listening on sign out ──
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            if !isAuth {
                print("User signed out — stopping listeners")
                inventoryManager.stopListening()
            }
        }
        // ── Also try on appear (in case onChange missed it) ──
        .onAppear {
            if let clinicID = authManager.currentUser?.clinicID,
               !clinicID.isEmpty,
               inventoryManager.items.isEmpty {
                print("onAppear — starting inventory listener")
                inventoryManager.startListening(clinicID: clinicID)
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Splash Screen
// ══════════════════════════════════════════════════════

struct SplashView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.primary)

            Text("ClinicStock")
                .font(AppFonts.largeTitle)
                .foregroundColor(AppColors.textPrimary)

            ProgressView()
                .progressViewStyle(
                    CircularProgressViewStyle(tint: AppColors.primary)
                )
                .scaleEffect(1.2)
                .padding(.top, AppSpacing.md)

            Text("Loading...")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}

#Preview {
    RootView()
        .environmentObject(AuthManager())
        .environmentObject(InventoryManager())
}
