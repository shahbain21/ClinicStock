//
//  ContentView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

// ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject var seeder = DatabaseSeeder()
    
    var body: some View {
        VStack(spacing: 24) {
            
            Spacer()
            
            // App icon
            Image(systemName: "cross.case.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("MedTrack")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            
            Text("Backend Setup")
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Status message
            Text(seeder.status)
                .font(.headline)
                .foregroundColor(seeder.isComplete ? .green : .primary)
                .multilineTextAlignment(.center)
                .padding()
            
            // Seed button
            if !seeder.isComplete {
                Button {
                    Task {
                        await seeder.seedDatabase()
                    }
                } label: {
                    if seeder.isSeeding {
                        HStack {
                            ProgressView()
                                .tint(.white)
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
                .disabled(seeder.isSeeding)
                .padding(.horizontal, 32)
            }
            
            // After seeding, show login info
            if seeder.isComplete {
                VStack(spacing: 12) {
                    Text("Your test login:")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Email:")
                                .foregroundColor(.secondary)
                            Text("admin@medtrack.com")
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Password:")
                                .foregroundColor(.secondary)
                            Text("Test1234!")
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
