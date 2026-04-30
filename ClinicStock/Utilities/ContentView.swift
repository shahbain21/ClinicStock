//
//  ContentView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  FIXES:
//  - Admin email/password are now user-supplied inputs instead of
//    hardcoded "admin@clinicstock.com" / "Test1234!".
//  - "Reset" buttons let you re-run seeders without tearing down the
//    whole settings flow.
//  - Errors from the seeders surface in the UI (previously buried in
//    the Xcode console).
//  - AppTheme tokens replace raw SwiftUI colors for visual consistency.
//  - Preview uses AuthManager.preview() so it doesn't touch Firebase.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject var seeder = DatabaseSeeder()
    @StateObject var catalogSeeder = CatalogSeeder()

    @State private var showInventoryOnlyConfirm = false
    @State private var showAllowIfExistingConfirm = false
    @State private var adminEmail = "admin@clinicstock.com"
    @State private var adminPassword = "Test1234!"

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {

                Spacer().frame(height: AppSpacing.lg)

                header

                clinicInfo

                Divider().padding(.horizontal, AppSpacing.xxxl)

                fullSeederSection

                Divider().padding(.horizontal, AppSpacing.xxxl)

                inventoryOnlySection

                Divider().padding(.horizontal, AppSpacing.xxxl)

                catalogSeederSection

                Spacer().frame(height: AppSpacing.xxxl)
            }
        }
        .appBackground()
        .alert("Seed Inventory?", isPresented: $showInventoryOnlyConfirm) {
            Button("Seed") {
                if let clinicID = authManager.effectiveClinicID,
                   !clinicID.isEmpty {
                    Task {
                        await seeder.seedInventoryOnly(clinicID: clinicID)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will add 18 sample inventory items to your current clinic. Only run this once.")
        }
        .alert("Project already has data", isPresented: $showAllowIfExistingConfirm) {
            Button("Seed anyway", role: .destructive) {
                Task {
                    await seeder.seedDatabase(
                        adminEmail: adminEmail,
                        adminPassword: adminPassword,
                        allowIfExisting: true
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clinics already exist in this project. Seeding anyway will create a new clinic alongside the existing ones. Continue?")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Sections
    // ══════════════════════════════════════════════════════

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.accent)

            Text("ClinicStock")
                .font(AppFonts.largeTitle)
                .foregroundColor(AppColors.textPrimary)

            Text("Backend Setup")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    @ViewBuilder
    private var clinicInfo: some View {
        if let clinic = authManager.currentClinic,
           let clinicID = clinic.id {
            VStack(spacing: AppSpacing.xs) {
                Text("Current Clinic: \(clinic.name)")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                Text("ID: \(clinicID)")
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textTertiary)
                    .textSelection(.enabled)
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .cornerRadius(AppRadius.small)
            .padding(.horizontal, AppSpacing.xxxl)
        }
    }

    private var fullSeederSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text("Full Database Setup")
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            // Admin credentials — editable, no longer hardcoded
            VStack(spacing: AppSpacing.sm) {
                TextField("Admin email", text: $adminEmail)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("Admin password", text: $adminPassword)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .disabled(seeder.isSeeding)

            Text(seeder.status)
                .font(AppFonts.caption)
                .foregroundColor(seeder.isComplete ? AppColors.success : AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            if let error = seeder.lastError {
                Text(error)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxxl)
            }

            Button {
                Task {
                    // Proactive pre-check so the user sees the confirmation
                    // dialog instead of a silent abort.
                    await seeder.seedDatabase(
                        adminEmail: adminEmail,
                        adminPassword: adminPassword,
                        allowIfExisting: false
                    )
                    // If seeder aborted due to existing data, prompt to
                    // allow override.
                    if seeder.lastError?.contains("allowIfExisting") == true {
                        showAllowIfExistingConfirm = true
                    }
                }
            } label: {
                if seeder.isSeeding {
                    HStack {
                        ProgressView().tint(.white)
                        Text("Setting up database...")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                } else {
                    HStack {
                        Image(systemName: "leaf.fill")
                        Text("Set Up New Database")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.success)
            .disabled(seeder.isSeeding || seeder.isComplete || adminEmail.isEmpty || adminPassword.isEmpty)
            .padding(.horizontal, AppSpacing.xxxl)

            if seeder.isComplete {
                Button("Reset") {
                    seeder.reset()
                }
                .font(AppFonts.caption)
                .foregroundColor(AppColors.accent)
            }
        }
    }

    private var inventoryOnlySection: some View {
        VStack(spacing: AppSpacing.md) {
            Text("Seed Inventory Only")
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            Text("Add sample inventory to your current clinic")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)

            Button {
                showInventoryOnlyConfirm = true
            } label: {
                HStack {
                    Image(systemName: "shippingbox.fill")
                    Text("Seed Inventory for Current Clinic")
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.warning)
            .disabled(
                seeder.isSeeding ||
                (authManager.effectiveClinicID?.isEmpty ?? true)
            )
            .padding(.horizontal, AppSpacing.xxxl)
        }
    }

    private var catalogSeederSection: some View {
        VStack(spacing: AppSpacing.md) {
            Text("HCPCS Catalog")
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            Text(catalogSeeder.status)
                .font(AppFonts.caption)
                .foregroundColor(catalogSeeder.isComplete ? AppColors.success : AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            if catalogSeeder.isSeeding {
                ProgressView(
                    value: Double(catalogSeeder.progress),
                    total: Double(max(catalogSeeder.total, 1))
                )
                .padding(.horizontal, AppSpacing.xxxl)
            }

            if let error = catalogSeeder.lastError {
                Text(error)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxxl)
            }

            Button {
                Task { await catalogSeeder.seedCatalog() }
            } label: {
                if catalogSeeder.isSeeding {
                    HStack {
                        ProgressView().tint(.white)
                        Text("Seeding... \(catalogSeeder.progress)/\(catalogSeeder.total)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                } else {
                    HStack {
                        Image(systemName: "list.bullet.rectangle.fill")
                        Text("Seed DME Catalog")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .disabled(catalogSeeder.isSeeding || catalogSeeder.isComplete)
            .padding(.horizontal, AppSpacing.xxxl)

            if catalogSeeder.isComplete {
                Button("Reset") {
                    catalogSeeder.reset()
                }
                .font(AppFonts.caption)
                .foregroundColor(AppColors.accent)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.preview())
}
