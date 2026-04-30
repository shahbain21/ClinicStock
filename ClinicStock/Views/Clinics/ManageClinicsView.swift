//
//  ManageClinicsView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/27/26.
//


//
//  ManageClinicsView.swift
//  ClinicStock
//
//  Platform-admin screen for managing the clinic portfolio:
//  archiving inactive clinics and restoring previously archived ones.
//
//  Reachable via Settings → Admin Tools → "Manage Clinics".
//
//  Behaviors:
//   - Active clinics show with an Archive button (red, destructive)
//   - The currently-active clinic's Archive button is disabled with
//     a tooltip-style label "Switch first" — admin must move out of
//     a clinic before archiving it
//   - "Show archived" toggle reveals archived clinics with Restore
//     buttons. Off by default to keep the active list clean.
//   - Archive and Restore are confirmed via alerts to prevent slips
//

import SwiftUI

struct ManageClinicsView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var clinics: [Clinic] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil

    @State private var showArchived = false

    @State private var clinicPendingArchive: Clinic? = nil
    @State private var clinicPendingRestore: Clinic? = nil

    @State private var actionInProgress = false
    @State private var actionError: String? = nil

    private var activeClinics: [Clinic] {
        clinics.filter { $0.isActive }
    }

    private var archivedClinics: [Clinic] {
        clinics.filter { !$0.isActive }
    }

    var body: some View {
        Group {
            if isLoading && clinics.isEmpty {
                loadingState
            } else if let error = loadError, clinics.isEmpty {
                errorState(message: error)
            } else {
                content
            }
        }
        .appBackground()
        .navigationTitle("Manage Clinics")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadClinics()
        }
        .refreshable {
            await loadClinics()
        }
        // Archive confirmation
        .alert(
            "Archive \(clinicPendingArchive?.name ?? "Clinic")?",
            isPresented: Binding(
                get: { clinicPendingArchive != nil },
                set: { if !$0 { clinicPendingArchive = nil } }
            )
        ) {
            Button("Archive", role: .destructive) {
                if let clinic = clinicPendingArchive {
                    Task { await performArchive(clinic) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clinic will be hidden from the picker and aggregate views. Inventory, users, and history are preserved. You can restore it from \"Show archived\".")
        }
        // Restore confirmation
        .alert(
            "Restore \(clinicPendingRestore?.name ?? "Clinic")?",
            isPresented: Binding(
                get: { clinicPendingRestore != nil },
                set: { if !$0 { clinicPendingRestore = nil } }
            )
        ) {
            Button("Restore") {
                if let clinic = clinicPendingRestore {
                    Task { await performRestore(clinic) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(clinicPendingRestore?.name ?? "This clinic") will reappear in the clinic picker and aggregate views.")
        }
        // Action error
        .alert(
            "Couldn't Complete",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Content
    // ══════════════════════════════════════════════════════

    private var content: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if activeClinics.isEmpty {
                    Text("No active clinics.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, AppSpacing.xl)
                } else {
                    activeSection
                }

                Divider()
                    .padding(.vertical, AppSpacing.sm)

                Toggle(isOn: $showArchived.animation()) {
                    Text("Show archived")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                }

                if showArchived {
                    archivedSection
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionLabel("ACTIVE")
            ForEach(activeClinics, id: \.id) { clinic in
                clinicRow(
                    clinic: clinic,
                    actionTitle: "Archive",
                    actionColor: AppColors.danger,
                    actionDisabled: isCurrentlyActive(clinic),
                    actionDisabledLabel: "Switch first"
                ) {
                    clinicPendingArchive = clinic
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSection: some View {
        if archivedClinics.isEmpty {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "archivebox")
                    .font(.system(size: 28))
                    .foregroundColor(AppColors.textTertiary)
                Text("No archived clinics")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionLabel("ARCHIVED")
                ForEach(archivedClinics, id: \.id) { clinic in
                    clinicRow(
                        clinic: clinic,
                        actionTitle: "Restore",
                        actionColor: AppColors.accent,
                        actionDisabled: false,
                        actionDisabledLabel: nil
                    ) {
                        clinicPendingRestore = clinic
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Row
    // ══════════════════════════════════════════════════════

    private func clinicRow(
        clinic: Clinic,
        actionTitle: String,
        actionColor: Color,
        actionDisabled: Bool,
        actionDisabledLabel: String?,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: clinic.isActive ? "building.2.fill" : "archivebox.fill")
                .font(.system(size: 20))
                .foregroundColor(clinic.isActive ? AppColors.accent : AppColors.textTertiary)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(
                        (clinic.isActive ? AppColors.accent : AppColors.textTertiary)
                            .opacity(0.15)
                    )
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(clinic.name)
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    if isCurrentlyActive(clinic) {
                        Text("CURRENT")
                            .font(AppFonts.footnoteMedium)
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(AppColors.accent.opacity(0.15))
                            )
                    }
                }
                if !clinic.address.isEmpty {
                    Text(clinic.fullAddress)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: AppSpacing.sm)

            Button(action: onAction) {
                Text(actionDisabled ? (actionDisabledLabel ?? actionTitle) : actionTitle)
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(actionDisabled ? AppColors.textTertiary : actionColor)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        Capsule().stroke(
                            actionDisabled ? AppColors.border : actionColor,
                            lineWidth: 1
                        )
                    )
            }
            .disabled(actionDisabled || actionInProgress)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    private func isCurrentlyActive(_ clinic: Clinic) -> Bool {
        return authManager.selectedClinicID == clinic.id
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.footnoteMedium)
            .foregroundColor(AppColors.textTertiary)
            .padding(.leading, AppSpacing.xs)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - States
    // ══════════════════════════════════════════════════════

    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("Loading clinics...")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(AppColors.warning)
            Text("Couldn't load clinics")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            Button("Try Again") {
                Task { await loadClinics() }
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Loading + actions
    // ══════════════════════════════════════════════════════

    private func loadClinics() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            clinics = try await DatabaseService.shared.getAllClinicsIncludingArchived()
        } catch {
            print("[ManageClinicsView] load error: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func performArchive(_ clinic: Clinic) async {
        guard let id = clinic.id else { return }
        actionInProgress = true
        defer { actionInProgress = false }

        do {
            try await authManager.archiveClinic(id)
            await loadClinics()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performRestore(_ clinic: Clinic) async {
        guard let id = clinic.id else { return }
        actionInProgress = true
        defer { actionInProgress = false }

        do {
            try await authManager.restoreClinic(id)
            await loadClinics()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    NavigationStack {
        ManageClinicsView()
            .environmentObject(AuthManager.preview())
    }
}