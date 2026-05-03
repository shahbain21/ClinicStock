//
//  ItemDetailView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  HIFI RESTRUCTURE:
//  - Product image placeholder at the top (SF Symbol for now; real image
//    upload is a future feature).
//  - Item name + LOT / HCPCS secondary row below image.
//  - Info cards restructured to match the hifi's card-per-field style:
//      Quantity card     (with "X items remaining until low stock"
//                         messaging instead of the generic 3-column)
//      Supplier card     (displays `manufacturer` labeled as "Supplier")
//      Last Restocked    (pulls from lastUpdated + lastUpdatedBy user)
//      Description card  (displays item.notes, prominent if non-empty)
//  - Actions retained: Check Out / Add Stock / Void / Edit / Remove.
//  - Void banner, stock warning banner, recent history section kept.
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
    @State private var lastRestockedByName: String?

    // 5 minute void window, matching PermissionManager's hardcoded value.
    private static let voidWindow: TimeInterval = 5 * 60

    // Live reference — updates flow through @Published inventoryManager.items.
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

    /// Banner appears if the user's MOST RECENT quantity action on
    /// this item was a checkout (still within the void window). After
    /// performing an undo, the most recent action becomes a void
    /// (a quantity-INCREASE), and the banner correctly disappears.
    ///
    /// Without this "most recent must be a checkout" check, tapping
    /// Undo would walk backwards through history voiding every prior
    /// checkout one at a time — because after each void, the filter
    /// would just find the next-older checkout in `recentLogs`.
    private var voidableRecentLog: HistoryLog? {
        guard let uid = authManager.currentUser?.id else { return nil }
        let cutoff = Date().addingTimeInterval(-Self.voidWindow)

        // Find the user's most recent quantityUpdate (in either
        // direction) for this item, within the void window. If that
        // most-recent action wasn't a checkout, return nil so the
        // banner stays hidden.
        let mostRecent = recentLogs.first { log in
            log.itemID == currentItem.id &&
            log.userID == uid &&
            log.action == .quantityUpdate &&
            log.timestamp >= cutoff
        }

        guard let candidate = mostRecent else { return nil }

        let prev = Int(candidate.previousValue) ?? 0
        let new = Int(candidate.newValue) ?? 0
        guard new < prev else {
            // Most recent action was a void or restock — banner stays
            // hidden until they do a new checkout.
            return nil
        }

        return candidate
    }

    // Last restock log — for the "Last Restocked" card.
    private var lastRestockLog: HistoryLog? {
        recentLogs.first { log in
            log.itemID == currentItem.id &&
            (log.action == .added ||
             (log.action == .quantityUpdate &&
              (Int(log.newValue) ?? 0) > (Int(log.previousValue) ?? 0)))
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Body
    // ══════════════════════════════════════════════════════

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                productImageBlock
                nameBlock

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

                quantityCard
                supplierCard
                lastRestockedCard

                if !currentItem.notes.isEmpty {
                    descriptionCard
                }

                otherDetailsCard
                historySection
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
        }
        .appBackground()
        .navigationTitle("Inventory Details")
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

    private var productImageBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground.opacity(0.5))
                .frame(height: 180)

            // Placeholder icon — real image upload is a future feature.
            // Using an SF Symbol that hints at the category when possible,
            // falling back to a generic "shippingbox" for unknown types.
            Image(systemName: categoryIconName)
                .font(.system(size: 60))
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // Best-effort mapping of common category names to SF Symbols.
    // Staff sees something more relevant than a plain box.
    private var categoryIconName: String {
        let cat = currentItem.category.lowercased()
        if cat.contains("orthopedic") || cat.contains("brace") { return "figure.walk" }
        if cat.contains("cervical") || cat.contains("neck") { return "person.bust" }
        if cat.contains("lumbar") || cat.contains("back") { return "figure.core.training" }
        if cat.contains("wound") { return "bandage" }
        if cat.contains("respiratory") { return "lungs" }
        if cat.contains("diabetic") { return "drop" }
        if cat.contains("compression") { return "figure.run" }
        if cat.contains("mobility") { return "figure.roll" }
        if cat.contains("electrical") || cat.contains("stim") { return "bolt" }
        return "shippingbox"
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(currentItem.name)
                .font(AppFonts.title2)
                .foregroundColor(AppColors.textPrimary)

            // "LOT #: 19140  HCPCS #: L9534" style row
            HStack(spacing: AppSpacing.md) {
                if !currentItem.lotNumber.isEmpty {
                    Text("LOT #: \(currentItem.lotNumber)")
                }
                Text("HCPCS #: \(currentItem.hcpcsCode)")
            }
            .font(AppFonts.caption)
            .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // ══════════════════════════════════════════════════════
    // MARK: - Info Cards (hifi layout)
    // ══════════════════════════════════════════════════════

    /// Big quantity display with contextual "X items remaining until low stock"
    /// messaging on the left.
    private var quantityCard: some View {
        HStack(alignment: .center, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Quantity:")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)

                Text(quantityMessage)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(currentItem.quantity)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(quantityColor)
                Text("Items")
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private var quantityMessage: String {
        if currentItem.isOutOfStock {
            return "Out of stock"
        }
        if currentItem.isLowStock {
            return "Below low stock threshold (\(currentItem.lowStockThreshold))"
        }
        let remaining = currentItem.quantity - currentItem.lowStockThreshold
        if remaining <= 0 {
            return "At low stock threshold"
        }
        return "\(remaining) items remaining until low stock"
    }

    /// Manufacturer displayed as "Supplier" per hifi naming.
    private var supplierCard: some View {
        HStack {
            Text("Supplier:")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Text(currentItem.manufacturer.isEmpty ? "—" : currentItem.manufacturer)
                .font(AppFonts.body)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    /// Shows the most recent "added" or "stock increase" log entry.
    /// Falls back to the item's lastUpdated if no restock log is in the
    /// loaded window.
    private var lastRestockedCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Last Restocked:")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)

            Text(lastRestockedMessage)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private var lastRestockedMessage: String {
        if let log = lastRestockLog {
            let dateStr = log.timestamp.formatted(
                .dateTime
                    .month(.abbreviated)
                    .day()
                    .year()
                    .hour()
                    .minute()
            )
            return "\(dateStr) by \(log.userName)"
        }
        // Fallback: item-level lastUpdated. Less specific (could be any
        // edit, not just a restock) but better than nothing.
        let dateStr = currentItem.lastUpdated.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )
        if let name = lastRestockedByName {
            return "\(dateStr) by \(name)"
        }
        return dateStr
    }

    /// Item description card — displays item.notes as a prominent
    /// prose paragraph when present.
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Item Description:")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)

            Text(currentItem.notes)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    /// Secondary details not covered by the hifi's dedicated cards.
    /// Kept so nothing on the model becomes invisible.
    @ViewBuilder
    private var otherDetailsCard: some View {
        let hasSize = !currentItem.size.isEmpty && currentItem.size != "N/A"
        let hasBarcode = !currentItem.barcode.isEmpty
        let hasCost = (currentItem.unitCost ?? 0) > 0
        let hasCategory = !currentItem.category.isEmpty

        if hasSize || hasBarcode || hasCost || hasCategory {
            VStack(spacing: 0) {
                sectionTitle("Additional Details")

                if hasCategory {
                    detailRow("Category", currentItem.category)
                }
                if hasSize {
                    detailRow("Size", currentItem.size)
                }
                if hasBarcode {
                    detailRow("Barcode", currentItem.barcode)
                }
                if hasCost, let cost = currentItem.unitCost {
                    detailRow("Unit Cost", String(format: "$%.2f", cost))
                    detailRow("Total Value", String(format: "$%.2f", currentItem.totalValue))
                }
                detailRow(
                    "Added",
                    currentItem.dateAdded.formatted(date: .abbreviated, time: .shortened)
                )
            }
            .padding(AppSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColors.cardBackground)
            )
            .cardShadow()
        }
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

        let clinicID = authManager.effectiveClinicID

        Task {
            do {
                try await inventoryManager.checkOut(
                    itemID: itemID,
                    amount: amount,
                    by: user,
                    clinicID: clinicID
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

        let clinicID = authManager.effectiveClinicID

        Task {
            do {
                try await inventoryManager.addStock(
                    itemID: itemID,
                    amount: amount,
                    by: user,
                    clinicID: clinicID
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

        let clinicID = authManager.effectiveClinicID
        let prev = Int(log.previousValue) ?? 0
        let new = Int(log.newValue) ?? 0
        let amount = prev - new

        Task {
            do {
                try await inventoryManager.voidCheckout(
                    itemID: itemID,
                    amount: amount,
                    checkoutTime: log.timestamp,
                    by: user,
                    clinicID: clinicID
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

        let clinicID = authManager.effectiveClinicID

        Task {
            do {
                try await inventoryManager.removeItem(
                    itemID: itemID,
                    by: user,
                    clinicID: clinicID
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadHistory() async {
        guard let itemID = currentItem.id,
              let clinicID = authManager.effectiveClinicID else {
            print("[ItemDetail] loadHistory: missing itemID or clinicID")
            return
        }

        isLoadingLogs = true
        defer { isLoadingLogs = false }

        do {
            let logs = try await DatabaseService.shared.getItemLogs(
                itemID: itemID,
                clinicID: clinicID,
                limit: 10
            )
            recentLogs = logs

            print("[ItemDetail] loadHistory loaded \(logs.count) logs")
            if let first = logs.first {
                print("[ItemDetail] most recent log: action=\(first.action.rawValue), userID=\(first.userID), prev=\(first.previousValue), new=\(first.newValue)")
                print("[ItemDetail] currentUser uid=\(authManager.currentUser?.id ?? "nil")")
                if let v = voidableRecentLog {
                    print("[ItemDetail] voidableRecentLog matches: \(v.id ?? "no id")")
                } else {
                    print("[ItemDetail] voidableRecentLog returned nil — no banner")
                }
            }

            // Try to resolve lastUpdatedBy for the fallback "Last Restocked"
            // display. Non-critical — silently ignore failures.
            if lastRestockLog == nil && !currentItem.lastUpdatedBy.isEmpty {
                if let user = try? await DatabaseService.shared.getUser(
                    userID: currentItem.lastUpdatedBy
                ) {
                    lastRestockedByName = user.displayName
                }
            }
        } catch {
            print("[ItemDetail] Failed to load history: \(error)")
            print("[ItemDetail] error details — code: \((error as NSError).code), domain: \((error as NSError).domain)")
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Quantity Adjust Sheet
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
        case .addStock: return 1000
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
            name: "Tens Unit",
            hcpcsCode: "L9534",
            lotNumber: "19140",
            size: "Universal",
            barcode: "012345678905",
            quantity: 71,
            originalQuantity: 80,
            lowStockThreshold: 2,
            clinicID: "preview-clinic",
            category: "Electrical Stimulation",
            manufacturer: "Viva Health",
            unitCost: 129.99,
            lastUpdatedBy: "admin",
            lastUpdated: Date(),
            dateAdded: Date().addingTimeInterval(-86400 * 30),
            notes: "The TENS Unit (Transcutaneous Electrical Nerve Stimulation) is a portable device used for pain relief by sending low-voltage electrical pulses through the skin. It helps reduce muscle pain, joint discomfort, and nerve-related pain by blocking pain signals and promoting natural endorphin release. The device is easy to use, adjustable in intensity, and commonly used for physical therapy, recovery, and chronic pain management."
        ))
    }
    .environmentObject(AuthManager.preview())
    .environmentObject(InventoryManager())
}
