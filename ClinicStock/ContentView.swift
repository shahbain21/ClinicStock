//
//  ContentView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject var seeder = DatabaseSeeder()
    @StateObject var catalogSeeder = CatalogSeeder()

    var body: some View {
        VStack(spacing: 24) {

            Spacer()

            Image(systemName: "cross.case.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("ClinicStock")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Backend Setup")
                .foregroundColor(.secondary)

            Spacer()

            // ── Database Seeder ──
            Text(seeder.status)
                .font(.headline)
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
                        Text("Set Up Database")
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
                VStack(spacing: 8) {
                    Text("Login: admin@clinicstock.com / Test1234!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .padding(.horizontal, 32)

            // ── Catalog Seeder ──
            Text(catalogSeeder.status)
                .font(.headline)
                .foregroundColor(catalogSeeder.isComplete ? .green : .primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if catalogSeeder.isSeeding {
                ProgressView(value: Double(catalogSeeder.progress), total: Double(max(catalogSeeder.total, 1)))
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

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
