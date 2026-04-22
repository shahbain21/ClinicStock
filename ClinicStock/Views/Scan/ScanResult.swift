//
//  ScanResult.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/21/26.
//


//
//  ScanResultView.swift
//  ClinicStock
//
//  Shown after the Scan tab resolves a barcode. Three states:
//
//    .itemInStock  — barcode matched an inventory item in this clinic.
//                    Primary action: check out. Secondary: view details,
//                    scan another.
//
//    .catalogOnly  — barcode matched a catalog entry but we don't have
//                    this item in stock yet. Editor+: "Add to Inventory".
//                    Staff: informational, tell an editor.
//
//    .notFound     — barcode wasn't recognized at all. Just "Try Again"
//                    / "Cancel".
//

import SwiftUI

enum ScanResult {
    case itemInStock(InventoryItem)
    case catalogOnly(HCPCSCatalogItem, gtin: String?)
    case notFound(scannedValue: String)
}

struct ScanResultView: View {

    let result: ScanResult

    var onCheckOut: (() -> Void)?
    var onViewDetails: (() -> Void)?
    var onAddToInventory: (() -> Void)?
    var onTryAgain: () -> Void
    var onDismiss: () -> Void

    @EnvironmentObject var authManager: AuthManager

    private var canAddStock: Bool {
        PermissionManager.canAddStock(role: authManager.currentUser?.role ?? .staff)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusHeader
                .padding(.top, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)

            contentCard
                .padding(.horizontal, AppSpacing.lg)

            Spacer()

            actionButtons
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
        }
        .appBackground()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Status Header
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var statusHeader: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: statusIcon)
                .font(.system(size: 56))
                .foregroundColor(statusColor)

            Text(statusTitle)
                .font(AppFonts.title2)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private var statusIcon: String {
        switch result {
        case .itemInStock: return "checkmark.circle.fill"
        case .catalogOnly: return "exclamationmark.circle.fill"
        case .notFound: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch result {
        case .itemInStock: return AppColors.success
        case .catalogOnly: return AppColors.warning
        case .notFound: return AppColors.danger
        }
    }

    private var statusTitle: String {
        switch result {
        case .itemInStock: return "Item Found"
        case .catalogOnly: return "Not in Stock"
        case .notFound: return "Not Recognized"
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Content Card
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var contentCard: some View {
        switch result {
        case .itemInStock(let item):
            inStockCard(item: item)
        case .catalogOnly(let catalog, _):
            catalogOnlyCard(catalog: catalog)
        case .notFound(let scannedValue):
            notFoundCard(value: scannedValue)
        }
    }

    private func inStockCard(item: InventoryItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(item.name)
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            if !item.lotNumber.isEmpty {
                detailLine(
                    label: "LOT #",
                    value: "\(item.lotNumber) · HCPCS #\(item.hcpcsCode)"
                )
            } else {
                detailLine(label: "HCPCS", value: item.hcpcsCode)
            }

            Divider()

            detailLine(label: "Category", value: item.category)

            if !item.size.isEmpty && item.size != "N/A" {
                detailLine(label: "Size", value: item.size)
            }

            HStack(alignment: .top) {
                Text("Current Stock")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(item.quantity)")
                    .font(AppFonts.title3)
                    .foregroundColor(currentStockColor(for: item))
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private func catalogOnlyCard(catalog: HCPCSCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(catalog.displayName)
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            detailLine(label: "HCPCS", value: catalog.hcpcsCode)
            detailLine(label: "Category", value: catalog.category)

            Divider()

            if canAddStock {
                Text("This item isn't in your clinic's inventory yet. Add it to start tracking.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            } else {
                Text("This item isn't in your clinic's inventory yet. Ask an editor to add it.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }

    private func notFoundCard(value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Scanned code")
                .font(AppFonts.captionSemibold)
                .foregroundColor(AppColors.textSecondary)

            Text(value)
                .font(AppFonts.body.monospaced())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(3)
                .truncationMode(.middle)

            Divider()

            Text("The scanned code isn't a valid HCPCS code or product barcode we can match. Try again, or search the catalog by name.")
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

    private func detailLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    private func currentStockColor(for item: InventoryItem) -> Color {
        if item.quantity <= 0 { return AppColors.danger }
        if item.isLowStock { return AppColors.warning }
        return AppColors.textPrimary
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Action Buttons
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var actionButtons: some View {
        switch result {
        case .itemInStock(let item):
            inStockActions(item: item)

        case .catalogOnly:
            catalogOnlyActions

        case .notFound:
            notFoundActions
        }
    }

    private func inStockActions(item: InventoryItem) -> some View {
        VStack(spacing: AppSpacing.md) {
            // Primary: Update quantity (checkout)
            if item.quantity > 0 {
                Button(action: { onCheckOut?() }) {
                    Text("Update Quantity")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.medium)
                                .fill(AppColors.accent)
                        )
                }
            } else {
                Text("Out of stock")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .fill(AppColors.danger.opacity(0.1))
                    )
            }

            // Secondary: View details
            Button(action: { onViewDetails?() }) {
                Text("View Details")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }

            // Tertiary: Scan another
            Button(action: onTryAgain) {
                Text("Scan Another Item")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.accent)
            }
            .padding(.top, AppSpacing.xs)
        }
    }

    private var catalogOnlyActions: some View {
        VStack(spacing: AppSpacing.md) {
            if canAddStock {
                Button(action: { onAddToInventory?() }) {
                    Text("Add to Inventory")
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.medium)
                                .fill(AppColors.accent)
                        )
                }
            }

            Button(action: onTryAgain) {
                Text("Scan Another Item")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }

            Button(action: onDismiss) {
                Text("Cancel")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.top, AppSpacing.xs)
        }
    }

    private var notFoundActions: some View {
        VStack(spacing: AppSpacing.md) {
            Button(action: onTryAgain) {
                Text("Try Again")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .fill(AppColors.accent)
                    )
            }

            Button(action: onDismiss) {
                Text("Cancel")
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .stroke(AppColors.border, lineWidth: 1)
                    )
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("In Stock") {
    ScanResultView(
        result: .itemInStock(InventoryItem(
            id: "preview",
            name: "LSO Brace",
            hcpcsCode: "L0625",
            lotNumber: "19149",
            size: "Universal",
            barcode: "012345678905",
            quantity: 51,
            originalQuantity: 60,
            lowStockThreshold: 10,
            clinicID: "preview-clinic",
            category: "Lumbar",
            manufacturer: "Breg",
            unitCost: 45.00,
            lastUpdatedBy: "admin",
            lastUpdated: Date(),
            dateAdded: Date(),
            notes: ""
        )),
        onCheckOut: {},
        onViewDetails: {},
        onTryAgain: {},
        onDismiss: {}
    )
    .environmentObject(AuthManager.preview())
}

#Preview("Catalog Only") {
    ScanResultView(
        result: .catalogOnly(
            HCPCSCatalogItem(
                hcpcsCode: "L1820",
                clinicalName: "Knee orthosis, elastic with joints",
                commonNames: ["knee brace"],
                category: "Orthopedic",
                gtins: [],
                isActive: true,
                sourceYear: 2026,
                lastUpdated: Date()
            ),
            gtin: "012345678905"
        ),
        onAddToInventory: {},
        onTryAgain: {},
        onDismiss: {}
    )
    .environmentObject(AuthManager.preview())
}

#Preview("Not Found") {
    ScanResultView(
        result: .notFound(scannedValue: "9999999999999"),
        onTryAgain: {},
        onDismiss: {}
    )
    .environmentObject(AuthManager.preview())
}