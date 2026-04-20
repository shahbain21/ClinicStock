//
//  ContentView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  UPDATED:
//  - Added "Seed Inventory Only" for existing clinics
//  - Shows current clinic ID for reference
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject var seeder = DatabaseSeeder()
    @StateObject var catalogSeeder = CatalogSeeder()

    @State private var showInventoryOnlyConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                Spacer().frame(height: 20)

                Image(systemName: "cross.case.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("ClinicStock")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Backend Setup")
                    .foregroundColor(.secondary)

                // ── Current Clinic Info ──
                if let clinic = authManager.currentClinic,
                   let clinicID = clinic.id {
                    VStack(spacing: 4) {
                        Text("Current Clinic: \(clinic.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("ID: \(clinicID)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .padding(.horizontal, 32)
                }

                Divider().padding(.horizontal, 32)

                // ══════════════════════════════════════
                // MARK: - Full Database Seeder
                // ══════════════════════════════════════

                VStack(spacing: 12) {
                    Text("Full Database Setup")
                        .font(.headline)

                    Text(seeder.status)
                        .font(.subheadline)
                        .foregroundColor(seeder.isComplete ? .green : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        Task { await seeder.seedDatabase() }
                    } label: {
                        if seeder.isSeeding {
                            HStack {
                                ProgressView().tint(.white)
                                Text("Setting up database...")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            HStack {
                                Image(systemName: "leaf.fill")
                                Text("Set Up New Database")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(seeder.isSeeding || seeder.isComplete)
                    .padding(.horizontal, 32)

                    if seeder.isComplete {
                        Text("Login: admin@clinicstock.com / Test1234!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider().padding(.horizontal, 32)

                // ══════════════════════════════════════
                // MARK: - Inventory Only Seeder
                // ══════════════════════════════════════

                VStack(spacing: 12) {
                    Text("Seed Inventory Only")
                        .font(.headline)

                    Text("Add sample inventory to your current clinic")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        showInventoryOnlyConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "shippingbox.fill")
                            Text("Seed Inventory for Current Clinic")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(
                        seeder.isSeeding ||
                        authManager.currentUser?.clinicID.isEmpty != false
                    )
                    .padding(.horizontal, 32)
                }

                Divider().padding(.horizontal, 32)

                // ══════════════════════════════════════
                // MARK: - Catalog Seeder
                // ══════════════════════════════════════

                VStack(spacing: 12) {
                    Text("HCPCS Catalog")
                        .font(.headline)

                    Text(catalogSeeder.status)
                        .font(.subheadline)
                        .foregroundColor(catalogSeeder.isComplete ? .green : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    if catalogSeeder.isSeeding {
                        ProgressView(
                            value: Double(catalogSeeder.progress),
                            total: Double(max(catalogSeeder.total, 1))
                        )
                        .padding(.horizontal, 32)
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
                            .padding()
                        } else {
                            HStack {
                                Image(systemName: "list.bullet.rectangle.fill")
                                Text("Seed DME Catalog")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(catalogSeeder.isSeeding || catalogSeeder.isComplete)
                    .padding(.horizontal, 32)
                }

                Spacer().frame(height: 40)
            }
        }
        .alert("Seed Inventory?", isPresented: $showInventoryOnlyConfirm) {
            Button("Seed") {
                if let clinicID = authManager.currentUser?.clinicID,
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}
