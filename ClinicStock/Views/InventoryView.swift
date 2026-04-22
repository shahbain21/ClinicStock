//
//  InventoryListView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/18/26.
//
//  FIXES:
//  - NavigationLink destination wired to real ItemDetailView.
//  - "Add An Item" sheet wired to real AddItemView.
//  - Dead showScanner state removed (scanner belongs with CatalogSearchView
//    and will be shared once extracted; scan buttons here were dead UI).
//  - Listener error banner at top of list so connection loss is visible
//    instead of masquerading as empty inventory.
//  - .safeAreaInset(edge: .bottom) replaces the magic 120pt bottom
//    padding. Bottom bar stacks correctly over the tab bar automatically.
//  - Sort menu shows checkmark on the active sort.
//  - Search trims whitespace before matching.
//  - Preview uses AuthManager.preview() + full environment.
//  - Duplicate header comments cleaned up.
//

import SwiftUI

struct InventoryListView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    @State private var searchText = ""
    @State private var selectedFilter: StockFilter = .all
    @State private var showAddItem = false
    @State private var sortOrder: SortOrder = .nameAsc

    enum StockFilter: String, CaseIterable {
        case all = "All"
        case low = "Low"
        case out = "Out"
    }

    enum SortOrder: Hashable {
        case nameAsc, nameDesc, qtyAsc, qtyDesc
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Derived data
    // ══════════════════════════════════════════════════════

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

        // Search — trim so whitespace-only queries don't distort results
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let query = trimmed.lowercased()
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

    private func countFor(_ filter: StockFilter) -> Int? {
        switch filter {
        case .all: return nil
        case .low: return inventoryManager.items.filter { $0.isLowStock && $0.quantity > 0 }.count
        case .out: return inventoryManager.items.filter { $0.quantity <= 0 }.count
        }
    }

    private var canAddStock: Bool {
        PermissionManager.canAddStock(role: authManager.currentUser?.role ?? .staff)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Body
    // ══════════════════════════════════════════════════════

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner
                searchBar
                filterBar
                listContent
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
                ItemDetailView(item: item)
            }
            .sheet(isPresented: $showAddItem) {
                AddItemView()
                    .environmentObject(authManager)
                    .environmentObject(inventoryManager)
            }
            .safeAreaInset(edge: .bottom) {
                if canAddStock {
                    bottomBar
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Subviews
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var connectionBanner: some View {
        if let error = inventoryManager.listenerError {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection issue")
                        .font(AppFonts.captionSemibold)
                        .foregroundColor(AppColors.textPrimary)
                    Text(error.localizedDescription)
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry") {
                    retryListener()
                }
                .font(AppFonts.captionSemibold)
                .foregroundColor(AppColors.accent)
            }
            .padding(AppSpacing.md)
            .background(AppColors.warningLight)
            .overlay(
                Rectangle()
                    .fill(AppColors.warning.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private var searchBar: some View {
        AppSearchBar(text: $searchText, placeholder: "Search")
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
    }

    private var filterBar: some View {
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

            sortMenu

            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
    }

    private var sortMenu: some View {
        Menu {
            sortButton(label: "Name A→Z", order: .nameAsc)
            sortButton(label: "Name Z→A", order: .nameDesc)
            sortButton(label: "Qty Low→High", order: .qtyAsc)
            sortButton(label: "Qty High→Low", order: .qtyDesc)
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
                    .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
            )
        }
    }

    private func sortButton(label: String, order: SortOrder) -> some View {
        Button {
            sortOrder = order
        } label: {
            if sortOrder == order {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if inventoryManager.isLoading && inventoryManager.items.isEmpty {
            Spacer()
            ProgressView("Loading inventory...")
                .foregroundColor(AppColors.textSecondary)
            Spacer()

        } else if filteredItems.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "shippingbox",
                title: searchText.isEmpty ? "No Items" : "No Results",
                message: searchText.isEmpty
                    ? "Add inventory items to get started"
                    : "Try a different search term"
            )
            Spacer()

        } else {
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
            }
        }
    }

    private var bottomBar: some View {
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
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(AppColors.background)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func retryListener() {
        guard let clinicID = authManager.currentUser?.clinicID else { return }
        inventoryManager.startListening(clinicID: clinicID)
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
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(UserManager())
        .environmentObject(HCPCSSearchService())
}
