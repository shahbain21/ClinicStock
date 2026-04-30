//
//  InventoryListView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/18/26.
//
//  LAYOUT FIXES:
//  - Search + filter pills grouped in a visually cohesive sticky header
//    with its own background matching the nav area, plus a subtle
//    divider at the bottom to separate from the scrolling list.
//  - List content now scrolls cleanly beneath the header — no more weird
//    "top of item card peeking" behind the filters.
//  - "Add An Item" bottom bar has a proper background + top shadow so
//    it doesn't look like it's floating on top of a list row.
//  - Increased padding between header, list, and bottom button so nothing
//    feels cramped.
//
//  PRIOR FIXES (carried forward):
//  - NavigationLink wired to real ItemDetailView.
//  - AddItemView sheet.
//  - Dead showScanner state removed.
//  - listenerError banner.
//  - .safeAreaInset for bottom bar.
//  - Sort menu checkmark on active sort.
//  - Search trims whitespace.
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

        switch selectedFilter {
        case .all:
            break
        case .low:
            items = items.filter { $0.isLowStock && $0.quantity > 0 }
        case .out:
            items = items.filter { $0.quantity <= 0 }
        }

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

    /// True when admin is viewing across all clinics. Hides the Add
    /// Item bar (no clinic context to add to) and switches the list
    /// to the aggregated grouped-by-product layout.
    private var isAggregateMode: Bool {
        authManager.isAggregateMode
    }

    /// Aggregated inventory rows, used in aggregate mode. Items are
    /// merged by (lowercased name, HCPCS, lot number) — same product
    /// at different locations gets one row with a per-clinic breakdown.
    /// We use lot number as part of the key so different lots of the
    /// same product still appear as separate rows (lot tracking matters
    /// for medical inventory).
    private var aggregatedRows: [AggregatedInventoryRow] {
        let groups = Dictionary(grouping: inventoryManager.items) { item in
            AggregatedInventoryRow.Key(
                name: item.name.lowercased(),
                hcpcsCode: item.hcpcsCode.uppercased(),
                lotNumber: item.lotNumber
            )
        }

        let rows = groups.map { _, items in
            AggregatedInventoryRow(items: items)
        }

        // Apply search/filter same as the per-clinic path
        let filtered = applyAggregateFilters(to: rows)
        return applyAggregateSort(to: filtered)
    }

    private func applyAggregateFilters(
        to rows: [AggregatedInventoryRow]
    ) -> [AggregatedInventoryRow] {
        var filtered = rows

        switch selectedFilter {
        case .all: break
        case .low:
            filtered = filtered.filter { $0.totalQuantity <= $0.lowestThreshold }
        case .out:
            filtered = filtered.filter { $0.totalQuantity == 0 }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            filtered = filtered.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.hcpcsCode.lowercased().contains(q) ||
                $0.lotNumber.lowercased().contains(q)
            }
        }

        return filtered
    }

    private func applyAggregateSort(
        to rows: [AggregatedInventoryRow]
    ) -> [AggregatedInventoryRow] {
        switch sortOrder {
        case .nameAsc:
            return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDesc:
            return rows.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .qtyAsc:
            return rows.sorted { $0.totalQuantity < $1.totalQuantity }
        case .qtyDesc:
            return rows.sorted { $0.totalQuantity > $1.totalQuantity }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Body
    // ══════════════════════════════════════════════════════

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionBanner

                // Sticky header: search + filters as one grouped unit
                headerBlock

                // Scrolling list — cleanly below the header, no bleed-through
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
                if canAddStock && !isAggregateMode {
                    bottomBar
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Header Block (search + filters together)
    // ══════════════════════════════════════════════════════

    private var headerBlock: some View {
        VStack(spacing: AppSpacing.md) {
            searchBar
            filterBar
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
        .background(
            AppColors.background
                // Subtle divider at the bottom to separate from list
                .overlay(
                    Rectangle()
                        .fill(AppColors.border.opacity(0.3))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Connection Banner
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

    // ══════════════════════════════════════════════════════
    // MARK: - Search + Filter
    // ══════════════════════════════════════════════════════

    private var searchBar: some View {
        AppSearchBar(text: $searchText, placeholder: "Search")
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

    // ══════════════════════════════════════════════════════
    // MARK: - List Content
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var listContent: some View {
        if inventoryManager.isLoading && inventoryManager.items.isEmpty {
            Spacer()
            ProgressView(isAggregateMode ? "Loading all clinics..." : "Loading inventory...")
                .foregroundColor(AppColors.textSecondary)
            Spacer()

        } else if isAggregateMode {
            aggregateListContent

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
                .padding(.bottom, AppSpacing.md)
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Aggregate-mode list. Rows show the merged-product totals plus
    /// a per-clinic breakdown beneath each. Pull-to-refresh re-fetches
    /// since aggregate mode doesn't use a real-time listener.
    @ViewBuilder
    private var aggregateListContent: some View {
        let rows = aggregatedRows

        if rows.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "square.grid.2x2",
                title: searchText.isEmpty ? "No Items Yet" : "No Results",
                message: searchText.isEmpty
                    ? "Add items in any clinic to see them here"
                    : "Try a different search term"
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(rows) { row in
                        AggregateInventoryRowView(row: row)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await inventoryManager.loadAggregateInventory()
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Bottom Action Bar
    // ══════════════════════════════════════════════════════

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Top divider — separates the button from scrolling content
            Rectangle()
                .fill(AppColors.border.opacity(0.3))
                .frame(height: 1)

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
        }
        .background(
            AppColors.background
                // Soft shadow at the top to separate from list content
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func retryListener() {
        guard let clinicID = authManager.effectiveClinicID else { return }
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
// MARK: - Aggregated row (cross-clinic merged item)
// ══════════════════════════════════════════════════════

/// One row in the aggregate-mode list. Represents the same product
/// (matched on name + HCPCS + lot) across all clinics that stock it.
struct AggregatedInventoryRow: Identifiable {
    struct Key: Hashable {
        let name: String
        let hcpcsCode: String
        let lotNumber: String
    }

    let items: [InventoryItem]

    var id: String {
        // Deterministic key for SwiftUI ForEach. Stable regardless of
        // item order because we sort the clinic IDs.
        let clinicSig = items
            .compactMap { $0.clinicID }
            .sorted()
            .joined(separator: "|")
        return "\(displayName)|\(hcpcsCode)|\(lotNumber)|\(clinicSig)"
    }

    var displayName: String {
        items.first?.name ?? "Unknown"
    }

    var hcpcsCode: String {
        items.first?.hcpcsCode.uppercased() ?? ""
    }

    var lotNumber: String {
        items.first?.lotNumber ?? ""
    }

    var category: String {
        items.first?.category ?? ""
    }

    var totalQuantity: Int {
        items.map { $0.quantity }.reduce(0, +)
    }

    /// Use the lowest threshold across locations as the "is this low"
    /// signal. If ANY location considers this item low, the row reads
    /// as low overall — better to over-warn than miss a shortage.
    var lowestThreshold: Int {
        items.map { $0.lowStockThreshold }.min() ?? 0
    }

    var isLow: Bool {
        totalQuantity > 0 && totalQuantity <= lowestThreshold
    }

    var isOut: Bool {
        totalQuantity == 0
    }

    /// Per-clinic breakdown rows. Each tuple = (clinicID, clinicName, qty).
    /// Sorted descending by quantity so the location with the most stock
    /// shows first.
    var perClinicBreakdown: [(clinicID: String, qty: Int)] {
        let grouped = Dictionary(grouping: items) { $0.clinicID ?? "" }
        return grouped
            .map { (clinicID, items) in
                (clinicID: clinicID,
                 qty: items.map { $0.quantity }.reduce(0, +))
            }
            .sorted { $0.qty > $1.qty }
    }
}

/// Card display for one aggregate row. Tapping is a no-op for now —
/// detail screens for aggregate items would require multi-clinic
/// editing flows we haven't designed yet. Admin can switch to a
/// specific clinic to view/edit a particular item.
struct AggregateInventoryRowView: View {
    let row: AggregatedInventoryRow

    @State private var clinicNames: [String: String] = [:]

    private var totalColor: Color {
        if row.isOut { return AppColors.danger }
        if row.isLow { return AppColors.warning }
        return AppColors.textPrimary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayName)
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: AppSpacing.xs) {
                        if !row.lotNumber.isEmpty {
                            Text("Lot \(row.lotNumber)")
                                .font(AppFonts.footnote)
                                .foregroundColor(AppColors.textSecondary)
                            Text("·")
                                .foregroundColor(AppColors.textTertiary)
                        }
                        Text(row.hcpcsCode)
                            .font(AppFonts.footnote)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(row.totalQuantity)")
                        .font(AppFonts.title3)
                        .foregroundColor(totalColor)
                    Text("total")
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            // Per-clinic breakdown chip row
            FlexibleHStack(spacing: AppSpacing.xs) {
                ForEach(row.perClinicBreakdown, id: \.clinicID) { entry in
                    clinicChip(
                        clinicName: clinicNames[entry.clinicID] ?? "…",
                        qty: entry.qty
                    )
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .task {
            await loadClinicNames()
        }
    }

    private func clinicChip(clinicName: String, qty: Int) -> some View {
        HStack(spacing: 4) {
            Text(clinicName)
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textSecondary)
            Text("\(qty)")
                .font(AppFonts.footnoteMedium)
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(AppColors.border.opacity(0.3))
        )
    }

    /// Resolve the clinicID → clinic name mapping for the breakdown
    /// chips. Cache so we don't re-fetch on every redraw.
    private func loadClinicNames() async {
        let neededIDs = Set(row.perClinicBreakdown.map { $0.clinicID })
            .subtracting(clinicNames.keys)
        guard !neededIDs.isEmpty else { return }

        for clinicID in neededIDs where !clinicID.isEmpty {
            if let clinic = try? await DatabaseService.shared.getClinic(clinicID: clinicID) {
                await MainActor.run {
                    self.clinicNames[clinicID] = clinic.name
                }
            }
        }
    }
}

/// Simple flexible horizontal stack that wraps to multiple lines.
/// Used for the clinic-chip breakdown row when there are many clinics.
struct FlexibleHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // For now, use a simple wrap-by-lazy-grid. Won't perfectly
        // pack chips of varying widths but is good enough for 3-10
        // clinics, which is realistic.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
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
