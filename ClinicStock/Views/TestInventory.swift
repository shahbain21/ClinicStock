//
//  TestInventory.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/6/26.
//

import SwiftUI

struct TestInventoryView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    
    var body: some View {
        NavigationStack {
            VStack {
                if inventoryManager.items.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading inventory..")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        // Low stock alert
                        if !inventoryManager.lowStockItems.isEmpty {
                            Section {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("\(inventoryManager.lowStockItems.count) items low on stock")
                                        .foregroundColor(.red)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                        
                        // Inventory items
                        Section("Inventory (\(inventoryManager.items.count) items)") {
                            ForEach(inventoryManager.items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.headline)
                                        HStack {
                                            Text(item.hcpcsCode)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                            Text("•")
                                                .font(.caption)
                                            Text("Size: \(item.size)")
                                                .font(.caption)
                                            Text("•")
                                                .font(.caption)
                                            Text(item.category)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(item.quantity)")
                                        .font(.title2.bold())
                                        .foregroundColor(
                                            item.isLowStock ? .red :
                                            item.quantity == 0 ? .gray : .green
                                        )
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("ClinicStock")
            .toolbar {
                // User info
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading) {
                        Text(authManager.currentUser?.displayName ?? "")
                            .font(.caption.bold())
                        Text(authManager.currentUser?.role.displayName ?? "")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                // Sign out
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        inventoryManager.stopListening()
                        authManager.signOut()
                    }
                    .font(.caption)
                }
            }
            .onAppear {
                // Start loading inventory when view appears
                if let clinicID = authManager.currentUser?.clinicID {
                    inventoryManager.startListening(clinicID: clinicID)
                }
            }
        }
    }
}
