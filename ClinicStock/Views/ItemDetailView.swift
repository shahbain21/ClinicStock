//
//  ItemDetailView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Item detail screen. Every role can check out. Editors and above can
//  add stock, edit, and remove. Anyone who made a recent checkout can
//  void it within 5 minutes.
//
//  The view watches inventoryManager.items for the current item by ID,
//  so real-time updates from the Firestore listener flow through.
//

import SwiftUI

struct ItemDetailView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @Environment(\.dismiss) private var dismiss

    let item: InventoryItem

    @State private var showCheckOutSheet = false
    @State private var showAddStockSheet = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var recentLogs: [HistoryLog] = []
    @State private var isLoadingLogs = false
    @State private var errorMessage: String?

    // 5 minute void window, matching PermissionManager's hardcoded value.
    private static let voidWindow: TimeInterval = 5 * 60

    // Live reference — when the Firestore listener updates this item,
    // the view reflects it via @Published inventoryManager.items.
    private var currentItem: InventoryItem {
        inventoryManager.items.first(where: { $0.id == item.id }) ?? item
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Permission helpers
    // ══════════════════════════════════════════════════════

    private var role: AppUser.UserRole {
        authManager.currentUser?.role ?? .staff
    }

    private var canCheckOut: Bool {
        PermissionManager.canCheckOut(role: role) && currentItem.quantity > 0
    }

    private var canAddStock: Bool {
        PermissionManager.canAddStock(role: role)
    }

    private var canEdit: Bool {
        PermissionManager.canEditItemInfo(role: role)
    }

    private var canRemove: Bool {
        PermissionManager.canRemoveStock(role: role)
    }

    // A recent checkout log by the current user, within the void window,
    // for this item.
    private var voidableRecentLog: HistoryLog? {
        guard let uid = authManager.currentUser?.id else { return nil }
        let cutoff = Date().addingTimeInterval(-Self.voidWindow)

        return recentLogs.first { log in
            log.itemID == currentItem.id &&
            log.userID == uid &&
            log.action == .quantityUpdate &&
            log.timestamp >= cutoff &&
            // Only checkouts — where quantity went down
            (Int(log.newValue) ?? 0) < (Int(log.previousValue) ?? 0)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Body
    // ══════════════════════════════════════════════════════

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                headerCard

                if currentItem.isLowStock || currentItem.isOutOfStock {
                    stockBanner
                }

                if let error = errorMessage {
                    errorBanner(error)
                }

                actionButtons

                if let voidable = voidableRecentLog {
                    voidBanner(log: voidable)
                }

                detailsCard

                historySection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
        }
        .appBackground()
        .navigationTitle(currentItem.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit || canRemove {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if canEdit {
                            Button {
                                showEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        if canRemove {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
        }
        .sheet(isPresented: $showCheckOutSheet) {
            QuantityAdjustSheet(
                mode: .checkOut,
                item: currentItem,
                onConfirm: { quantity in
                    checkOut(amount: quantity)
                }
            )
            .environmentObject(authManager)
            .environmentObject(inventoryManager)
        }
        .sheet(isPresented: $showAddStockSheet) {
            QuantityAdjustSheet(
                mode: .addStock,
                item: currentItem,
                onConfirm: { quantity in
                    addStock(amount: quantity)
                }
            )
            .environmentObject(authManager)
            .environmentObject(inventoryManager)
        }
        .sheet(isPresented: $showEditSheet) {
            AddItemView(editingItem: currentItem)
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
        }
        .alert("Remove Item?", isPresented: $showDeleteConfirm) {
            Button("Remove", role: .destructive) {
                removeItem()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(currentItem.name) will be permanently removed. This cannot be undone.")
        }
        .task {
            await loadHistory()
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Sections
    // ══════════════════════════════════════════════════════

    private var headerCard: some View {
        VStack(spacing: AppSpacing.md) {
            Text(currentItem.name)
                .font(AppFonts.title2)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: AppSpacing.sm) {
                badge(text: currentItem.hcpcsCode, color: AppColors.accent)
                badge(text: currentItem.category, color: AppColors.textSecondary)
                if !currentItem.size.isEmpty && currentItem.size != "N/A" {
                    badge(text: currentItem.size, color: AppColors.textSecondary)
                }
            }

            HStack(spacing: AppSpacing.xxl) {
                quantityDisplay(
                    value: "\(currentItem.quantity)",
                    label: "On hand",
                    color: quantityColor
                )
                quantityDisplay(
                    value: "\(currentItem.quantityUsed)",
                    label: "Used",
                    color: AppColors.textSecondary
                )
                quantityDisplay(
                    value: "\(currentItem.lowStockThreshold)",
                    label: "Low at",
                    color: AppColors.textSecondary
                )
            }
            .padding(.top, AppSpacing.md)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private var stockBanner: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(currentItem.isOutOfStock ? AppColors.danger : AppColors.warning)
            Text(currentItem.isOutOfStock ? "Out of stock" : "Low stock")
                .font(AppFonts.captionSemibold)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(
                    currentItem.isOutOfStock
                        ? AppColors.danger.opacity(0.1)
                        : AppColors.warning.opacity(0.1)
                )
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(AppFonts.caption)
            Spacer()
            Button("Dismiss") { errorMessage = nil }
                .font(AppFonts.footnote)
        }
        .foregroundColor(AppColors.danger)
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.danger.opacity(0.1))
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: AppSpacing.md) {
            if canCheckOut {
                actionButton(
                    title: "Check Out",
                    icon: "arrow.down.circle.fill",
                    color: AppColors.accent,
                    action: { showCheckOutSheet = true }
                )
            }

            if canAddStock {
                actionButton(
                    title: "Add Stock",
                    icon: "plus.circle.fill",
                    color: AppColors.success,
                    action: { showAddStockSheet = true }
                )
            }
        }
    }

    private func voidBanner(log: HistoryLog) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundColor(AppColors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recent checkout")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text("You can void this within 5 minutes")
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button("Void") {
                voidCheckout(log: log)
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(
                Capsule().stroke(AppColors.accent, lineWidth: 1)
            )
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.accent.opacity(0.08))
        )
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            sectionTitle("Details")

            detailRow("HCPCS Code", currentItem.hcpcsCode)
            detailRow("Category", currentItem.category)
            if !currentItem.size.isEmpty {
                detailRow("Size", currentItem.size)
            }
            if !currentItem.lotNumber.isEmpty {
                detailRow("Lot Number", currentItem.lotNumber)
            }
            if !currentItem.barcode.isEmpty {
                detailRow("Barcode", currentItem.barcode)
            }
            if !currentItem.manufacturer.isEmpty {
                detailRow("Manufacturer", currentItem.manufacturer)
            }
            if let cost = currentItem.unitCost, cost > 0 {
                detailRow("Unit Cost", String(format: "$%.2f", cost))
                detailRow("Total Value", String(format: "$%.2f", currentItem.totalValue))
            }
            if !currentItem.notes.isEmpty {
                detailRow("Notes", currentItem.notes)
            }
            detailRow("Added", currentItem.dateAdded.formatted(date: .abbreviated, time: .shortened))
            detailRow("Last Updated", currentItem.lastUpdated.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    @ViewBuilder
    private var historySection: some View {
        VStack(spacing: 0) {
            sectionTitle("Recent History")

            if isLoadingLogs {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, AppSpacing.xl)

            } else if recentLogs.isEmpty {
                Text("No history yet")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.vertical, AppSpacing.lg)

            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(recentLogs) { log in
                        HistoryLogRow(log: log)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Subview Helpers
    // ══════════════════════════════════════════════════════

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(AppFonts.footnoteMedium)
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(color))
    }

    private func quantityDisplay(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFonts.title2)
                .foregroundColor(color)
            Text(label)
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                Text(title)
            }
            .font(AppFonts.bodySemibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(color)
            )
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .padding(.bottom, AppSpacing.md)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var quantityColor: Color {
        if currentItem.quantity <= 0 { return AppColors.danger }
        if currentItem.isLowStock { return AppColors.warning }
        return AppColors.success
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func checkOut(amount: Int) {
        guard let user = authManager.currentUser,
              let itemID = currentItem.id else { return }

        Task {
            do {
                try await inventoryManager.checkOut(
                    itemID: itemID,
                    amount: amount,
                    by: user
                )
                await loadHistory()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addStock(amount: Int) {
        guard let user = authManager.currentUser,
              let itemID = currentItem.id else { return }

        Task {
            do {
                try await inventoryManager.addStock(
                    itemID: itemID,
                    amount: amount,
                    by: user
                )
                await loadHistory()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func voidCheckout(log: HistoryLog) {
        guard let user = authManager.currentUser,
              let itemID = currentItem.id else { return }

        let prev = Int(log.previousValue) ?? 0
        let new = Int(log.newValue) ?? 0
        let amount = prev - new

        Task {
            do {
                try await inventoryManager.voidCheckout(
                    itemID: itemID,
                    amount: amount,
                    checkoutTime: log.timestamp,
                    by: user
                )
                await loadHistory()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeItem() {
        guard let user = authManager.currentUser,
              let itemID = currentItem.id else { return }

        Task {
            do {
                try await inventoryManager.removeItem(itemID: itemID, by: user)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadHistory() async {
        guard let itemID = currentItem.id,
              let clinicID = authManager.currentUser?.clinicID else { return }

        isLoadingLogs = true
        defer { isLoadingLogs = false }

        do {
            recentLogs = try await DatabaseService.shared.getItemLogs(
                itemID: itemID,
                clinicID: clinicID,
                limit: 10
            )
        } catch {
            print("Failed to load history: \(error)")
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Quantity Adjust Sheet
//
// Shared sheet for checkout and add-stock. Mode determines label,
// button color, and max allowed.
// ══════════════════════════════════════════════════════

struct QuantityAdjustSheet: View {

    enum Mode {
        case checkOut
        case addStock

        var title: String {
            switch self {
            case .checkOut: return "Check Out"
            case .addStock: return "Add Stock"
            }
        }

        var actionLabel: String {
            switch self {
            case .checkOut: return "Check Out"
            case .addStock: return "Add Stock"
            }
        }

        var icon: String {
            switch self {
            case .checkOut: return "arrow.down.circle.fill"
            case .addStock: return "plus.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .checkOut: return AppColors.accent
            case .addStock: return AppColors.success
            }
        }
    }

    let mode: Mode
    let item: InventoryItem
    let onConfirm: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int = 1

    private var maxAllowed: Int {
        switch mode {
        case .checkOut: return item.quantity
        case .addStock: return 1000  // Arbitrary sanity cap
        }
    }

    private var isValid: Bool {
        quantity > 0 && quantity <= maxAllowed
    }

    private var newQuantity: Int {
        switch mode {
        case .checkOut: return item.quantity - quantity
        case .addStock: return item.quantity + quantity
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xxl) {
                VStack(spacing: AppSpacing.sm) {
                    Text(item.name)
                        .font(AppFonts.title3)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Currently: \(item.quantity) on hand")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                HStack(spacing: AppSpacing.xl) {
                    Button {
                        if quantity > 1 { quantity -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(quantity > 1 ? mode.color : AppColors.border)
                    }
                    .disabled(quantity <= 1)

                    Text("\(quantity)")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(minWidth: 100)

                    Button {
                        if quantity < maxAllowed { quantity += 1 }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(quantity < maxAllowed ? mode.color : AppColors.border)
                    }
                    .disabled(quantity >= maxAllowed)
                }

                HStack(spacing: AppSpacing.md) {
                    Text("After:")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Text("\(newQuantity) on hand")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                Button(action: {
                    onConfirm(quantity)
                    dismiss()
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: mode.icon)
                        Text(mode.actionLabel)
                    }
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .fill(isValid ? mode.color : AppColors.border)
                    )
                }
                .disabled(!isValid)
            }
            .padding(AppSpacing.xl)
            .appBackground()
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// ══════════════════════════════════════════════════════
// MARK: - History Log Row
// ══════════════════════════════════════════════════════

struct HistoryLogRow: View {
    let log: HistoryLog

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: log.action.icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.details)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                Text("\(log.userName) • \(log.timestamp.formatted(.relative(presentation: .named)))")
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    NavigationStack {
        ItemDetailView(item: InventoryItem(
            id: "preview",
            name: "Knee Brace",
            hcpcsCode: "L1820",
            lotNumber: "A12345",
            size: "L",
            barcode: "012345678905",
            quantity: 8,
            originalQuantity: 20,
            lowStockThreshold: 10,
            clinicID: "preview-clinic",
            category: "Orthopedic",
            manufacturer: "Breg",
            unitCost: 45.00,
            lastUpdatedBy: "admin",
            lastUpdated: Date(),
            dateAdded: Date().addingTimeInterval(-86400 * 30),
            notes: ""
        ))
    }
    .environmentObject(AuthManager.preview())
    .environmentObject(InventoryManager())
}
