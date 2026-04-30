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
                // Platform admin with no clinic picked yet → let them pick
                if authManager.needsClinicSelection {
                    ClinicPickerView()
                } else {
                    MainTabView()
                }

            } else {
                LoginView()
            }
        }
        // ── Inventory listener lifecycle ──
        //
        // .task(id:) runs when the view first appears AND whenever the
        // effective clinicID changes. This covers:
        //   - Fresh launch with a cached session
        //   - Sign-in (clinicID goes from nil → "abc123")
        //   - Platform admin switching clinics (clinicID changes)
        //   - Platform admin entering/leaving aggregate mode
        //
        // When the id changes, SwiftUI cancels the previous task, so
        // startListening is safely called exactly once per clinic.
        //
        // Aggregate mode triggers a different load path: one-shot
        // cross-clinic fetch instead of a real-time listener.
        //
        .task(id: routeKey) {
            if authManager.isAggregateMode {
                print("Loading aggregate inventory across all clinics")
                await inventoryManager.loadAggregateInventory()
            } else if let clinicID = authManager.effectiveClinicID,
                      !clinicID.isEmpty {
                print("Starting inventory listener for clinic: \(clinicID)")
                inventoryManager.startListening(clinicID: clinicID)
            } else {
                print("No effective clinic — stopping inventory listener")
                inventoryManager.stopListening()
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

    /// A composite key that captures the full "what context are we in"
    /// state. Changes to this key trigger a re-evaluation of which
    /// loading path to take. Without this we'd have to set up two
    /// separate .task blocks, which can't both observe the same id.
    private var routeKey: String {
        if authManager.isAggregateMode {
            return "aggregate"
        }
        return authManager.effectiveClinicID ?? "none"
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
