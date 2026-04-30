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

    @State private var showArchiveConfirm = false
    @State private var clinicToArchive: Clinic?
    @State private var archiveError: String?

    private var isAdmin: Bool {
        authManager.currentUser?.role == .admin
    }

    /// Show the "Archive This Clinic" section only when:
    /// - Platform admin (only they can archive clinics)
    /// - Currently viewing a specific clinic (not aggregate, not nothing)
    /// Aggregate or no-selection mode hides it because there's no
    /// single clinic to archive.
    private var shouldShowArchiveCurrentClinic: Bool {
        return authManager.isPlatformAdmin
            && !authManager.isAggregateMode
            && authManager.currentClinic != nil
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

                    if shouldShowArchiveCurrentClinic {
                        archiveCurrentClinicSection
                    }

                    logoutButton
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxl)
            }
            .appBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                "Archive Clinic?",
                isPresented: $showArchiveConfirm,
                presenting: clinicToArchive
            ) { clinic in
                Button("Archive", role: .destructive) {
                    Task { await archiveClinic(clinic) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { clinic in
                Text("\(clinic.name) will be hidden from the clinic picker and aggregate views. Its data is preserved and can be restored anytime from Archived Clinics.")
            }
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
                // Platform admin (multi-clinic owner) gets a "Switch
                // Clinic" row showing the currently-active clinic. Tap
                // to clear the selection and return to ClinicPickerView.
                if authManager.isPlatformAdmin {
                    Button {
                        authManager.clearClinicSelection()
                    } label: {
                        settingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Switch Clinic",
                            detail: switchClinicDetailLabel
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CreateClinicView()
                    } label: {
                        settingsRow(
                            icon: "plus.square.fill",
                            title: "Create New Clinic"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ManageClinicsView()
                    } label: {
                        settingsRow(
                            icon: "building.2.fill",
                            title: "Manage Clinics"
                        )
                    }
                    .buttonStyle(.plain)
                }

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

    /// "Archive This Clinic" destructive button. Sits below the main
    /// content, above logout, so it's discoverable but doesn't compete
    /// with primary admin tools. Only visible to platform admin while
    /// viewing a specific clinic.
    @ViewBuilder
    private var archiveCurrentClinicSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("CLINIC ACTIONS")

            Button {
                clinicToArchive = authManager.currentClinic
                showArchiveConfirm = true
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.danger)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Archive This Clinic")
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.danger)
                        if let name = authManager.currentClinic?.name {
                            Text(name)
                                .font(AppFonts.footnote)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Spacer()
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity)
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

            if let archiveError {
                Text(archiveError)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.danger)
                    .padding(.horizontal, AppSpacing.xs)
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Row helpers
    // ══════════════════════════════════════════════════════

    /// Trailing detail label for the platform admin's "Switch Clinic"
    /// row. Reflects current session state:
    ///  - aggregate mode → "All Clinics"
    ///  - specific clinic selected → the clinic's name
    ///  - neither (shouldn't happen since RootView routes elsewhere) → nil
    private var switchClinicDetailLabel: String? {
        if authManager.isAggregateMode {
            return "All Clinics"
        }
        return authManager.currentClinic?.name
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.footnoteMedium)
            .foregroundColor(AppColors.textTertiary)
            .padding(.leading, AppSpacing.xs)
    }

    private func settingsRow(
        icon: String,
        title: String,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 24)

            Text(title)
                .font(AppFonts.body)
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // Optional trailing detail (e.g. current clinic name on the
            // Switch Clinic row). Shown in a muted color before the chevron.
            if let detail = detail, !detail.isEmpty {
                Text(detail)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

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

    private func archiveClinic(_ clinic: Clinic) async {
        guard let id = clinic.id else { return }
        archiveError = nil

        do {
            try await authManager.archiveClinic(id)
            // archiveClinic clears the selection if we were viewing
            // this clinic — RootView will route us back to the picker
            // automatically. No manual navigation needed here.
        } catch {
            archiveError = error.localizedDescription
        }
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
