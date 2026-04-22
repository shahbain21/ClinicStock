//
//  SettingsView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  HIFI RESTRUCTURE:
//  - Switched from native List to a custom layout matching the hifi:
//    small-caps section labels (PROFILE, ADMIN TOOLS), big pill-shaped
//    rows with icon + label + chevron.
//  - Dropped the Clinic section (name/address). Not in hifi.
//  - Dropped email and role badge from the profile row. Just "Name" +
//    "Role" text per hifi.
//  - Staff / editor / manager / non-admin users now see profile + sign
//    out only. Admin Tools is admin-gated.
//  - Developer section (Database Tools) moved to its own labeled section
//    at the bottom, still behind #if DEBUG. Won't ship to production.
//  - Added Low Stock Threshold row (destination stubbed — screen to be
//    built next).
//  - Export Options row intentionally hidden. Will be added when the
//    Export screen is built.
//  - Logout button matches the hifi: red outlined pill at the bottom.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    private var isAdmin: Bool {
        authManager.currentUser?.role == .admin
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    profileSection

                    if isAdmin {
                        adminToolsSection
                    }

                    #if DEBUG
                    if isAdmin {
                        developerSection
                    }
                    #endif

                    Spacer(minLength: AppSpacing.lg)

                    logoutButton
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Profile
    // ══════════════════════════════════════════════════════

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("PROFILE")
            profilePill
        }
    }

    private var profilePill: some View {
        HStack(spacing: AppSpacing.md) {
            UserAvatar(
                name: authManager.currentUser?.displayName ?? "U",
                role: authManager.currentUser?.role ?? .staff,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(authManager.currentUser?.displayName ?? "User")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text((authManager.currentUser?.role ?? .staff).displayName)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Admin Tools
    // ══════════════════════════════════════════════════════

    private var adminToolsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("ADMIN TOOLS")

            VStack(spacing: AppSpacing.md) {
                NavigationLink {
                    UserManagementView()
                } label: {
                    settingsRow(
                        icon: "person.2.fill",
                        title: "User Management"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LowStockThresholdView()
                } label: {
                    settingsRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Low Stock Threshold"
                    )
                }
                .buttonStyle(.plain)

                // Export Options row intentionally omitted until the
                // Export screen exists. Add back as:
                //
                //   NavigationLink { ExportView() } label: {
                //       settingsRow(icon: "arrow.down.doc.fill",
                //                   title: "Export Options")
                //   }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Developer (DEBUG only)
    // ══════════════════════════════════════════════════════

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("DEVELOPER")

            NavigationLink {
                ContentView()
            } label: {
                settingsRow(
                    icon: "wrench.and.screwdriver.fill",
                    title: "Database Tools"
                )
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // ══════════════════════════════════════════════════════
    // MARK: - Logout
    // ══════════════════════════════════════════════════════

    private var logoutButton: some View {
        Button(action: signOut) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("LOGOUT")
            }
            .font(AppFonts.bodySemibold)
            .foregroundColor(AppColors.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .stroke(AppColors.danger.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Row helpers
    // ══════════════════════════════════════════════════════

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.footnoteMedium)
            .foregroundColor(AppColors.textTertiary)
            .padding(.leading, AppSpacing.xs)
    }

    private func settingsRow(icon: String, title: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 24)

            Text(title)
                .font(AppFonts.body)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func signOut() {
        // RootView tears down listeners reactively when isAuthenticated
        // flips; no manual cleanup needed here.
        authManager.signOut()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Low Stock Threshold (temporary stub)
//
// Real screen coming next. This stub is here so the NavigationLink in
// Settings compiles and staff can see the route working. Replace with
// the real LowStockThresholdView when built.
// ══════════════════════════════════════════════════════

struct LowStockThresholdView: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)
            Text("Coming soon")
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)
            Text("Global low stock threshold configuration")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle("Low Stock Threshold")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Admin") {
    SettingsView()
        .environmentObject(AuthManager.preview(
            isAuthenticated: true,
            currentUser: nil,
            currentClinic: nil
        ))
}

#Preview("Staff") {
    SettingsView()
        .environmentObject(AuthManager.preview(
            isAuthenticated: true,
            currentUser: nil,
            currentClinic: nil
        ))
}
