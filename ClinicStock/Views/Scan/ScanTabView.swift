//
//  ScanTabView.swift
//  ClinicStock
//
//  The Scan tab. Fast-checkout surface for staff.
//
//  NEW:
//  - In-stock scans briefly show the result screen (1.5s) then auto-
//    navigate to the full Item Detail page. The result screen was a
//    confirmation-only step for in-stock matches — the detail page has
//    every action the result screen offered plus more context.
//  - The result screen still appears for the other cases (catalogOnly,
//    unmatchedGTIN, notFound) where the user needs to choose an action.
//

import SwiftUI

struct ScanTabView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @EnvironmentObject var searchService: HCPCSSearchService

    @State private var showScanner = false
    @State private var isLookingUp = false
    @State private var scanResult: ScanOutcome? = nil

    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    // Auto-advance task for in-stock scans → Item Detail.
    @State private var autoAdvanceTask: Task<Void, Never>? = nil

    @State private var itemForCheckout: InventoryItem? = nil
    @State private var itemForDetail: InventoryItem? = nil

    @State private var addItemPrefill: AddItemPrefill? = nil
    @State private var gtinToLink: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                if isLookingUp {
                    lookingUpView
                } else if let result = scanResult {
                    ScanResultView(
                        result: result,
                        onCheckOut: { handleCheckOut(result: result) },
                        onViewDetails: { handleViewDetails(result: result) },
                        onAddToInventory: { handleAddToInventory(result: result) },
                        onLinkToExisting: { handleLinkToExisting(result: result) },
                        onTryAgain: {
                            cancelAutoAdvance()
                            scanResult = nil
                            showScanner = true
                        },
                        onDismiss: {
                            cancelAutoAdvance()
                            scanResult = nil
                        }
                    )
                    .environmentObject(authManager)
                } else {
                    idleView
                }

                if let message = toastMessage {
                    VStack {
                        toastBanner(message: message)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.md)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: toastMessage)
            .animation(.easeInOut(duration: 0.2), value: scanResult != nil)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { value in
                    showScanner = false
                    Task {
                        await lookup(scannedValue: value)
                    }
                }
            }
            .sheet(item: $itemForCheckout) { item in
                QuantityAdjustSheet(
                    mode: .checkOut,
                    item: item,
                    onConfirm: { quantity in
                        performCheckout(item: item, quantity: quantity)
                    }
                )
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
            }
            .sheet(item: $addItemPrefill) { prefill in
                AddItemView(
                    prefillName: prefill.name,
                    prefillHCPCS: prefill.hcpcsCode,
                    prefillBarcode: prefill.barcode,
                    prefillCategory: prefill.category,
                    prefillLotNumber: prefill.lotNumber
                )
                .environmentObject(authManager)
                .environmentObject(inventoryManager)
            }
            .sheet(item: $gtinToLink.asIdentifiableString) { identifiable in
                CatalogSearchView(
                    initialPendingGTIN: identifiable.value,
                    onLinkComplete: { linkedGTIN, catalogItem in
                        handleLinkComplete(gtin: linkedGTIN, item: catalogItem)
                    }
                )
                .environmentObject(searchService)
            }
            .navigationDestination(item: $itemForDetail) { item in
                ItemDetailView(item: item)
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Subviews
    // ══════════════════════════════════════════════════════

    private var idleView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 80))
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: AppSpacing.sm) {
                Text("Scan an item")
                    .font(AppFonts.title2)
                    .foregroundColor(AppColors.textPrimary)
                Text("Scan a barcode to check out stock, or look up an item not in your inventory.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            Button(action: { showScanner = true }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "barcode.viewfinder")
                    Text("Tap to Scan")
                }
                .font(AppFonts.bodySemibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColors.accent)
                )
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    private var lookingUpView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Looking up...")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private func toastBanner(message: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.success)
            Text(message)
                .font(AppFonts.captionSemibold)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(AppColors.success.opacity(0.3), lineWidth: 1)
                )
        )
        .cardShadow()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Lookup
    // ══════════════════════════════════════════════════════

    private func lookup(scannedValue: String) async {
        guard let clinicID = authManager.currentUser?.clinicID else { return }

        isLookingUp = true
        defer { isLookingUp = false }

        #if DEBUG
        print("[ScanTab] lookup starting — raw: \(scannedValue)")
        #endif

        do {
            if let item = try await inventoryManager.lookupBarcode(
                barcode: scannedValue,
                clinicID: clinicID
            ) {
                #if DEBUG
                print("[ScanTab] matched inventory item: \(item.name)")
                #endif
                scanResult = .itemInStock(item)
                scheduleAutoAdvance(to: item)
                return
            }
        } catch {
            print("[ScanTab] inventory lookup error: \(error)")
        }

        let catalogResult = await searchService.lookupBarcode(scannedValue)
        switch catalogResult {
        case .found(let catalogItem, let gtin):
            #if DEBUG
            print("[ScanTab] matched catalog: \(catalogItem.hcpcsCode)")
            #endif
            scanResult = .catalogOnly(catalogItem, gtin: gtin)

        case .gtinNotFound(let gtin, let parsed):
            #if DEBUG
            print("[ScanTab] unmatched GTIN: \(gtin) (lot=\(parsed.lotNumber ?? "-"), productCode=\(parsed.productCode ?? "-"))")
            #endif
            scanResult = .unmatchedGTIN(gtin: gtin, parsed: parsed)

        case .unrecognized:
            #if DEBUG
            print("[ScanTab] unrecognized — parser couldn't find GTIN or HCPCS")
            #endif
            scanResult = .notFound(scannedValue: scannedValue)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Auto-advance for in-stock scans
    //
    // The result screen is redundant for in-stock matches since the
    // Item Detail page has every action (check out, add stock, view
    // history, edit) plus more context. We show the confirmation
    // briefly for positive feedback, then push detail.
    // ══════════════════════════════════════════════════════

    private func scheduleAutoAdvance(to item: InventoryItem) {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }

            await MainActor.run {
                // Only advance if the user hasn't interacted in the meantime.
                // If they tapped "Scan Another", "View Details", or dismissed,
                // scanResult will have already changed.
                if case .itemInStock = scanResult {
                    scanResult = nil
                    itemForDetail = item
                }
            }
        }
    }

    private func cancelAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Result actions
    // ══════════════════════════════════════════════════════

    private func handleCheckOut(result: ScanOutcome) {
        guard case .itemInStock(let item) = result else { return }
        // User tapped the button — cancel auto-advance so we don't fire
        // the detail navigation mid-checkout.
        cancelAutoAdvance()
        itemForCheckout = item
    }

    private func handleViewDetails(result: ScanOutcome) {
        guard case .itemInStock(let item) = result else { return }
        cancelAutoAdvance()
        scanResult = nil
        itemForDetail = item
    }

    private func handleAddToInventory(result: ScanOutcome) {
        cancelAutoAdvance()
        scanResult = nil

        switch result {
        case .catalogOnly(let catalog, let gtin):
            addItemPrefill = AddItemPrefill(
                name: catalog.displayName,
                hcpcsCode: catalog.hcpcsCode,
                barcode: gtin ?? "",
                category: catalog.category,
                lotNumber: nil
            )

        case .unmatchedGTIN(let gtin, let parsed):
            addItemPrefill = AddItemPrefill(
                name: nil,
                hcpcsCode: nil,
                barcode: gtin,
                category: nil,
                lotNumber: parsed.lotNumber
            )

        default:
            addItemPrefill = AddItemPrefill(
                name: nil,
                hcpcsCode: nil,
                barcode: nil,
                category: nil,
                lotNumber: nil
            )
        }
    }

    private func handleLinkToExisting(result: ScanOutcome) {
        guard case .unmatchedGTIN(let gtin, _) = result else { return }
        cancelAutoAdvance()
        scanResult = nil
        gtinToLink = gtin
    }

    private func handleLinkComplete(gtin: String, item: HCPCSCatalogItem) {
        gtinToLink = nil
        showToast("Linked \(gtin) → \(item.displayName)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Checkout
    // ══════════════════════════════════════════════════════

    private func performCheckout(item: InventoryItem, quantity: Int) {
        guard let user = authManager.currentUser,
              let itemID = item.id else { return }

        Task {
            do {
                try await inventoryManager.checkOut(
                    itemID: itemID,
                    amount: quantity,
                    by: user
                )
                scanResult = nil
                showToast("Checked out \(quantity) · \(item.name)")
            } catch {
                showToast("Error: \(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - AddItem Prefill
// ══════════════════════════════════════════════════════

private struct AddItemPrefill: Identifiable {
    let id = UUID()
    let name: String?
    let hcpcsCode: String?
    let barcode: String?
    let category: String?
    let lotNumber: String?
}

// ══════════════════════════════════════════════════════
// MARK: - Identifiable String binding helper
// ══════════════════════════════════════════════════════

private struct IdentifiableString: Identifiable {
    var value: String
    var id: String { value }
}

private extension Binding where Value == String? {
    var asIdentifiableString: Binding<IdentifiableString?> {
        Binding<IdentifiableString?>(
            get: {
                self.wrappedValue.map(IdentifiableString.init(value:))
            },
            set: { newValue in
                self.wrappedValue = newValue?.value
            }
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ScanTabView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(HCPCSSearchService())
}
