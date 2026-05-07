//
//  LowStockThresholdView.swift
//  ClinicStock
//
//  Admin-configurable global low-stock threshold. When admin saves a
//  new value, it's bulk-applied to every item across every clinic —
//  including items with previously-set custom thresholds. The save
//  flow goes through a confirmation alert spelling out the scope of
//  the change before anything is written.
//
//  Tradeoff: simple mental model (one number, applied everywhere)
//  vs. loss of per-item customization. Chose simple. If per-item
//  customization becomes important later, the Item Detail screen
//  already supports editing an individual item's threshold (which
//  takes precedence until the next bulk apply).
//
//  Future: per-item statistical thresholds (computed from usage
//  history) can layer on top of this — the suggestion appears on
//  Item Detail and admin chooses whether to apply.
//

import SwiftUI

struct LowStockThresholdView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var threshold: Int = 10
    @State private var originalThreshold: Int = 10

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadError: String? = nil

    // Confirmation alert before bulk-applying the new threshold.
    @State private var showApplyConfirmation = false

    // Result alert after the bulk update finishes — reports how many
    // items were updated (and how many failed, if any).
    @State private var bulkResult: BulkUpdateResult? = nil

    private struct BulkUpdateResult: Identifiable {
        let id = UUID()
        let succeeded: Int
        let failed: Int

        var title: String {
            failed == 0 ? "All Items Updated" : "Update Partially Complete"
        }

        var message: String {
            if failed == 0 {
                return "\(succeeded) item\(succeeded == 1 ? "" : "s") updated to the new threshold."
            } else {
                return "\(succeeded) item\(succeeded == 1 ? "" : "s") updated successfully. \(failed) failed — try again or check that you have permission to edit those clinics."
            }
        }
    }

    private var canEdit: Bool {
        // Only admins can change settings (rules enforce this too).
        authManager.currentUser?.role == .admin
    }

    private var hasChanges: Bool {
        threshold != originalThreshold
    }

    var body: some View {
        Group {
            if isLoading {
                loadingState
            } else if let error = loadError {
                errorState(message: error)
            } else {
                content
            }
        }
        .appBackground()
        .navigationTitle("Low Stock Threshold")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadThreshold()
        }
        // Confirmation before bulk-applying. Spelled out so admin
        // understands this overwrites custom thresholds globally.
        .alert(
            "Apply \(threshold) to all items?",
            isPresented: $showApplyConfirmation
        ) {
            Button("Apply to All", role: .destructive) {
                Task { await save() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will set the low-stock threshold to \(threshold) for every item across every clinic, overwriting any custom values. This can't be undone.")
        }
        // Result reporting after bulk update finishes.
        .alert(
            bulkResult?.title ?? "",
            isPresented: Binding(
                get: { bulkResult != nil },
                set: { if !$0 { bulkResult = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(bulkResult?.message ?? "")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - States
    // ══════════════════════════════════════════════════════

    private var loadingState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("Loading...")
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
            Text("Couldn't load setting")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            Button("Try Again") {
                Task { await loadThreshold() }
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Content
    // ══════════════════════════════════════════════════════

    private var content: some View {
        VStack(spacing: AppSpacing.xl) {

            // Stepper card
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.warning)

                Text("Default Threshold")
                    .font(AppFonts.title3)
                    .foregroundColor(AppColors.textPrimary)

                Text("Items will be marked as 'low stock' when their quantity drops to or below this value.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.md)

                stepperRow
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.cardBackground)
            )
            .padding(.horizontal, AppSpacing.lg)

            // Behavior note
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppColors.accent)
                    Text("How this works")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                }

                Text("When you save a new value, it's applied to every item across every clinic — including items with custom thresholds. You'll be asked to confirm first.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.accent.opacity(0.08))
            )
            .padding(.horizontal, AppSpacing.lg)

            Spacer()

            // Save button
            if canEdit {
                Button {
                    showApplyConfirmation = true
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: .white)
                                )
                        } else {
                            Text("Save")
                        }
                    }
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .fill(hasChanges ? AppColors.primary : AppColors.border)
                    )
                }
                .disabled(!hasChanges || isSaving)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            } else {
                Text("Only admins can change this setting.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, AppSpacing.lg)
            }
        }
        .padding(.top, AppSpacing.xl)
    }

    private var stepperRow: some View {
        HStack(spacing: AppSpacing.xl) {
            Button(action: decrement) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(threshold > 0 && canEdit ? AppColors.accent : AppColors.border)
            }
            .disabled(threshold <= 0 || !canEdit)

            Text("\(threshold)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .frame(minWidth: 80)
                .contentTransition(.numericText())

            Button(action: increment) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(canEdit ? AppColors.accent : AppColors.border)
            }
            .disabled(!canEdit)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func increment() {
        withAnimation(.easeInOut(duration: 0.15)) {
            threshold += 1
        }
    }

    private func decrement() {
        guard threshold > 0 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            threshold -= 1
        }
    }

    private func loadThreshold() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let value = try await DatabaseService.shared.getLowStockDefault()
            threshold = value
            originalThreshold = value
        } catch {
            print("[LowStockThreshold] load error: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            // Write the new default first. If only this succeeds and
            // bulk apply fails, future items still pick up the new
            // value — partial success is recoverable.
            try await DatabaseService.shared.setLowStockDefault(threshold)

            // Bulk apply to existing items.
            let result = try await DatabaseService.shared.applyLowStockThresholdToAllItems(threshold)

            originalThreshold = threshold

            // Show the result alert. (Skip the "Saved" toast — the
            // result alert is more informative and we don't want both.)
            bulkResult = BulkUpdateResult(
                succeeded: result.succeeded,
                failed: result.failed
            )

        } catch {
            print("[LowStockThreshold] save error: \(error)")
            loadError = error.localizedDescription
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    NavigationStack {
        LowStockThresholdView()
            .environmentObject(AuthManager.preview())
    }
}
