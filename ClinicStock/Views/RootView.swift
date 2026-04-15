//
//  RootView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Root auth gate — decides which screen to show.
//  Also starts/stops inventory listener when auth changes.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        Group {
            if authManager.isLoading {
                // ── Splash Screen ──
                SplashView()

            } else if authManager.isAuthenticated {
                // ── Main App ──
                MainTabView()
                    .onAppear {
                        startListening()
                    }
                    .onChange(of: authManager.isAuthenticated) { _, isAuth in
                        if !isAuth {
                            inventoryManager.stopListening()
                        }
                    }

            } else {
                // ── Login ──
                LoginView()
            }
        }
    }

    private func startListening() {
        guard let clinicID = authManager.currentUser?.clinicID,
              !clinicID.isEmpty
        else { return }

        inventoryManager.startListening(clinicID: clinicID)
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
