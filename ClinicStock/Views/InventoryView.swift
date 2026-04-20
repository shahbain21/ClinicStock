//
//  InventoryView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/18/26.
//

//
//  InventoryListView.swift
//  ClinicStock
//

//
//  InventoryListView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//

import SwiftUI

struct InventoryListView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    @State private var searchText = ""
    @State private var selectedFilter: StockFilter = .all
    @State private var showAddItem = false
    @State private var showScanner = false
    @State private var sortOrder: SortOrder = .nameAsc

    enum StockFilter: String, CaseIterable {
        case all = "All"
        case low = "Low"
        case out = "Out"
    }

    enum SortOrder {
        case nameAsc, nameDesc, qtyAsc, qtyDesc
    }

    // ── Filtered + sorted items ──
    var filteredItems: [InventoryItem] {
        var items = inventoryManager.items

        // Filter
        switch selectedFilter {
        case .all:
            break
        case .low:
            items = items.filter { $0.isLowStock && $0.quantity > 0 }
        case .out:
            items = items.filter { $0.quantity <= 0 }
        }

        // Search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(query) ||
                $0.hcpcsCode.lowercased().contains(query) ||
                $0.barcode.lowercased().contains(query) ||
                $0.lotNumber.lowercased().contains(query) ||
                $0.category.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOrder {
        case .nameAsc:
            items.sort { $0.name < $1.name }
        case .nameDesc:
            items.sort { $0.name > $1.name }
        case .qtyAsc:
            items.sort { $0.quantity < $1.quantity }
        case .qtyDesc:
            items.sort { $0.quantity > $1.quantity }
        }

        return items
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Search Bar ──
                HStack(spacing: AppSpacing.md) {
                    AppSearchBar(text: $searchText, placeholder: "Search")

                    Button(action: { showScanner = true }) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)

                // ── Filter Pills ──
                HStack(spacing: AppSpacing.sm) {
                    ForEach(StockFilter.allCases, id: \.self) { filter in
                        FilterPill(
                            title: filter.rawValue,
                            count: countFor(filter),
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                            }
                        }
                    }

                    // Sort button
                    Menu {
                        Button("Name A→Z") { sortOrder = .nameAsc }
                        Button("Name Z→A") { sortOrder = .nameDesc }
                        Button("Qty Low→High") { sortOrder = .qtyAsc }
                        Button("Qty High→Low") { sortOrder = .qtyDesc }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12))
                            Text("Sort")
                                .font(AppFonts.captionMedium)
                        }
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            Capsule()
                                .fill(AppColors.cardBackground)
                                .overlay(
                                    Capsule().stroke(AppColors.border, lineWidth: 1)
                                )
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)

                // ── Loading ──
                if inventoryManager.isLoading {
                    Spacer()
                    ProgressView("Loading inventory...")
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                }
                // ── Empty State ──
                else if filteredItems.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "shippingbox",
                        title: searchText.isEmpty ? "No Items" : "No Results",
                        message: searchText.isEmpty
                            ? "Add inventory items to get started"
                            : "Try a different search term"
                    )
                    Spacer()
                }
                // ── Item List ──
                else {
                    ScrollView {
                        LazyVStack(spacing: AppSpacing.sm) {
                            ForEach(filteredItems) { item in
                                NavigationLink(value: item) {
                                    InventoryItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, 120) // Space for bottom buttons + tab bar
                    }
                }

                // ── Bottom Action Buttons ──
                if PermissionManager.canAddStock(role: authManager.currentUser?.role ?? .staff) {
                    HStack(spacing: AppSpacing.md) {
                        Button(action: { showAddItem = true }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add An Item")
                            }
                            .font(AppFonts.bodySemibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(AppColors.accent)
                            )
                        }

                        Button(action: { showScanner = true }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "barcode.viewfinder")
                                Text("Scan An Item")
                            }
                            .font(AppFonts.bodySemibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(AppColors.primary)
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.background)
                }
            }
            .appBackground()
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBell()
                }
            }
            .navigationDestination(for: InventoryItem.self) { item in
                // TODO: Replace with ItemDetailView
                Text("Detail for \(item.name)")
            }
            .sheet(isPresented: $showAddItem) {
                // TODO: Replace with AddItemView
                Text("Add Item")
            }
        }
    }

    // ── Count helper ──
    private func countFor(_ filter: StockFilter) -> Int? {
        switch filter {
        case .all: return nil
        case .low: return inventoryManager.items.filter { $0.isLowStock && $0.quantity > 0 }.count
        case .out: return inventoryManager.items.filter { $0.quantity <= 0 }.count
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Inventory Item Row
// ══════════════════════════════════════════════════════

struct InventoryItemRow: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(item.name)
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)

                HStack(spacing: AppSpacing.sm) {
                    if !item.lotNumber.isEmpty {
                        Text("LOT #:\(item.lotNumber)")
                    }
                    Text("HCPCS #:\(item.hcpcsCode)")
                }
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            // Quantity badge
            VStack(spacing: 2) {
                Text("\(item.quantity)")
                    .font(AppFonts.quantitySmall)
                    .foregroundColor(quantityColor)
                Text("Items")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(minWidth: 50)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .fill(quantityColor.opacity(0.1))
            )
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private var quantityColor: Color {
        if item.quantity <= 0 { return AppColors.danger }
        if item.isLowStock { return AppColors.warning }
        return AppColors.success
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Filter Pill
// ══════════════════════════════════════════════════════

struct FilterPill: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFonts.captionMedium)
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(AppFonts.footnoteMedium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? .white.opacity(0.3)
                                    : AppColors.danger.opacity(0.15)
                            )
                        )
                }
            }
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(
                Capsule().fill(
                    isSelected ? AppColors.primary : AppColors.cardBackground
                )
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.clear : AppColors.border,
                    lineWidth: 1
                )
            )
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Notification Bell
// ══════════════════════════════════════════════════════

struct NotificationBell: View {
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell.fill")
                .font(.system(size: 18))
                .foregroundColor(AppColors.textPrimary)

            if inventoryManager.lowStockItems.count > 0 {
                Circle()
                    .fill(AppColors.danger)
                    .frame(width: 10, height: 10)
                    .offset(x: 3, y: -3)
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    InventoryListView()
        .environmentObject(AuthManager())
        .environmentObject(InventoryManager())
}
