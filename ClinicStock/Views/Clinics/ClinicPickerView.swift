//
//  ClinicPickerView.swift
//  ClinicStock
//
//  Landing screen for platform-admin accounts. Shown by RootView when
//  the admin is authenticated but hasn't selected a clinic yet.
//
//  The admin picks one clinic from the list — that selection is the
//  "context" for the rest of the app session. Settings has a
//  "Switch Clinic" row that returns here.
//
//  Single-clinic users (everyone else) never see this screen — they're
//  pinned to their own clinic by user.clinicID.
//
//  NOTE: phase 1 shows only the per-clinic list. Phase 2 adds an
//  "All Clinics" aggregate option at the top.
//

import SwiftUI

struct ClinicPickerView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var clinics: [Clinic] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Choose Clinic")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                        .foregroundColor(AppColors.danger)
                    }
                }
                .task {
                    await loadClinics()
                }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Content
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingState
        } else if let error = loadError {
            errorState(message: error)
        } else if clinics.isEmpty {
            emptyState
        } else {
            clinicList
        }
    }

    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("Loading clinics...")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
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
        .appBackground()
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)
            Text("No Clinics Yet")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Text("Create a clinic to get started. (Phase 2 will add a 'Create Clinic' button here.)")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }

    private var clinicList: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Text("Select the clinic you're working with today.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, AppSpacing.xs)

                // "All Clinics" meta-option for platform admin. Enters
                // aggregate mode — Dashboard shows cross-clinic summary,
                // Inventory lists items merged across clinics. Write
                // actions (Add Item, Scan, Checkout) are disabled in
                // this mode since they need a specific clinic context.
                Button {
                    authManager.selectAggregateMode()
                } label: {
                    allClinicsRow
                }
                .buttonStyle(.plain)

                // Subtle divider between "All" and the per-clinic list
                Rectangle()
                    .fill(AppColors.border.opacity(0.3))
                    .frame(height: 1)
                    .padding(.vertical, AppSpacing.xs)

                ForEach(clinics, id: \.id) { clinic in
                    Button {
                        Task {
                            await authManager.selectClinic(clinic.id ?? "")
                        }
                    } label: {
                        clinicRow(clinic)
                    }
                    .buttonStyle(.plain)
                    .disabled(clinic.id == nil)
                }
            }
            .padding(AppSpacing.lg)
        }
        .appBackground()
    }

    private var allClinicsRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 20))
                .foregroundColor(AppColors.warning)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(AppColors.warning.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("All Clinics")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text("Aggregate view across \(clinics.count) location\(clinics.count == 1 ? "" : "s")")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    private func clinicRow(_ clinic: Clinic) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 20))
                .foregroundColor(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(AppColors.accent.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(clinic.name)
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                if !clinic.address.isEmpty {
                    Text(clinic.fullAddress)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Loading
    // ══════════════════════════════════════════════════════

    private func loadClinics() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            clinics = try await DatabaseService.shared.getAllClinics()
        } catch {
            print("[ClinicPicker] load error: \(error)")
            loadError = error.localizedDescription
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ClinicPickerView()
        .environmentObject(AuthManager.preview())
}
