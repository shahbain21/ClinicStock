//
//  RootView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  FIXES:
//  - Single source of truth for the inventory listener lifecycle.
//    Previously both RootView and MainTabView called startListening,
//    which meant every sign-in tore down and recreated the Firestore
//    listener 2-3 times.
//  - .task(id:) replaces the old .onAppear + .onChange combo. .task(id:)
//    runs when the view appears AND whenever the id changes, which is
//    exactly what we want for "start listening when we know the clinic."
//  - Listener teardown on sign-out stays in .onChange(of: isAuthenticated)
//    — view code (SettingsPlaceholder.signOut) no longer needs to call
//    stopListening manually.
//  - #Preview uses AuthManager.preview() so previews don't crash trying
//    to reach Firebase.
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
        // ── Inventory listener lifecycle ──
        //
        // .task(id:) runs when the view first appears AND whenever the
        // clinicID changes. This covers:
        //   - Fresh launch with a cached session (clinicID appears)
        //   - Sign-in (clinicID goes from nil → "abc123")
        //   - Clinic switch, if we ever add one (clinicID changes)
        //
        // When the id changes, SwiftUI cancels the previous task, so
        // startListening is safely called exactly once per clinic.
        //
        .task(id: authManager.currentUser?.clinicID) {
            if let clinicID = authManager.currentUser?.clinicID,
               !clinicID.isEmpty {
                print("Starting inventory listener for clinic: \(clinicID)")
                inventoryManager.startListening(clinicID: clinicID)
            }
        }
        // ── Stop listening on sign-out ──
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            if !isAuth {
                print("User signed out — stopping listeners")
                inventoryManager.stopListening()
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

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Splash") {
    SplashView()
}

#Preview("Logged Out") {
    RootView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(UserManager())
        .environmentObject(HCPCSSearchService())
}
