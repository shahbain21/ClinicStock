//
//  SettingsView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/20/26.
//


//
//  SettingsView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Extracted from the "SettingsPlaceholder" previously inside MainTabView.
//  Despite the old name it was already a real settings screen.
//
//  FIXES:
//  - Sign-out no longer manually calls inventoryManager.stopListening().
//    RootView tears listeners down reactively when isAuthenticated flips.
//  - Redundant .environmentObject(authManager) on the ContentView link
//    removed — the environment already propagates.
//  - Database Tools navigation link wrapped in #if DEBUG so destructive
//    dev tooling doesn't ship to production users.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                profileSection
                clinicSection

                if authManager.currentUser?.role == .admin {
                    adminSection
                }

                signOutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Sections
    // ══════════════════════════════════════════════════════

    private var profileSection: some View {
        Section {
            HStack(spacing: AppSpacing.lg) {
                UserAvatar(
                    name: authManager.currentUser?.displayName ?? "U",
                    role: authManager.currentUser?.role ?? .staff,
                    size: 50
                )

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(authManager.currentUser?.displayName ?? "User")
                        .font(AppFonts.bodySemibold)
                    Text(authManager.currentUser?.email ?? "")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                    RoleBadge(role: authManager.currentUser?.role ?? .staff)
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var clinicSection: some View {
        Section("Clinic") {
            LabeledContent(
                "Name",
                value: authManager.currentClinic?.name ?? "—"
            )
            LabeledContent(
                "Location",
                value: authManager.currentClinic?.fullAddress ?? "—"
            )
        }
    }

    private var adminSection: some View {
        Section("Admin") {
            NavigationLink {
                UserManagementView()
            } label: {
                Label("User Management", systemImage: "person.2.fill")
            }

            #if DEBUG
            // Dev-only. Destructive operations (seed, reset) live here,
            // so we gate it behind DEBUG so release builds don't expose it
            // to admins who could accidentally wipe their clinic data.
            NavigationLink {
                ContentView()
            } label: {
                Label("Database Tools (Dev)", systemImage: "wrench.and.screwdriver.fill")
            }
            #endif
        }
    }

    private var signOutSection: some View {
        Section {
            Button(action: signOut) {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.danger)
                    Spacer()
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func signOut() {
        // RootView's .onChange(of: isAuthenticated) tears down the
        // inventory listener when this flips. No manual cleanup needed.
        authManager.signOut()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Staff") {
    SettingsView()
        .environmentObject(AuthManager.preview(
            isAuthenticated: true,
            currentUser: nil,
            currentClinic: nil
        ))
}

#Preview("Admin") {
    SettingsView()
        .environmentObject(AuthManager.preview(
            isAuthenticated: true,
            currentUser: nil,
            currentClinic: nil
        ))
}