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

    /// Tracks a recently-completed checkout that can still be undone
    /// from the toast. When non-nil, the toast renders an "Undo"
    /// button. Cleared when the toast dismisses or the user navigates
    /// away. The 10-second window here is shorter than the 5-min
    /// permission window — this is just the toast lifetime, not a
    /// hard deadline. Users can still void via Item Detail / History
    /// for the full 5 min.
    @State private var pendingUndo: UndoableCheckout? = nil

    struct UndoableCheckout: Equatable {
        let itemID: String
        let itemName: String
        let quantity: Int
        let timestamp: Date
    }

    @State private var itemForCheckout: InventoryItem? = nil
    @State private var itemForDetail: InventoryItem? = nil

    @State private var addItemPrefill: AddItemPrefill? = nil

    /// State for the GTIN-linking sheet. We store both the GTIN (the
    /// catalog needs that as the link target) AND the original scan's
    /// parsed barcode (lot number, etc.) so we can carry it through
    /// to AddItemView after linking completes — saving the user from
    /// having to scan a second time just to add the item to inventory.
    @State private var pendingLinkContext: PendingLinkContext? = nil

    struct PendingLinkContext: Identifiable {
        let id = UUID()
        let gtin: String
        let parsed: ParsedBarcode?
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.background.ignoresSafeArea()

                if isLookingUp {
                    lookingUpView
                } else if authManager.isAggregateMode {
                    aggregateDisabledState
                } else if let result = scanResult {
                    ScanResultView(
                        result: result,
                        onCheckOut: { handleCheckOut(result: result) },
                        onViewDetails: { handleViewDetails(result: result) },
                        onAddToInventory: { handleAddToInventory(result: result) },
                        onLinkToExisting: { handleLinkToExisting(result: result) },
                        onTryAgain: {
                            scanResult = nil
                            showScanner = true
                        },
                        onDismiss: {
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
            .sheet(item: $pendingLinkContext) { context in
                CatalogSearchView(
                    initialPendingGTIN: context.gtin,
                    onLinkComplete: { linkedGTIN, catalogItem in
                        handleLinkComplete(
                            gtin: linkedGTIN,
                            item: catalogItem,
                            context: context
                        )
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

    /// Shown when platform admin is in "All Clinics" aggregate mode.
    /// Scanning needs a specific clinic context (which clinic gets the
    /// checkout? which clinic do we add new stock to?), so we guide
    /// admin to switch clinics in Settings rather than presenting an
    /// ambiguous flow.
    private var aggregateDisabledState: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: AppSpacing.sm) {
                Text("Pick a Clinic to Scan")
                    .font(AppFonts.title3)
                    .foregroundColor(AppColors.textPrimary)
                Text("Scanning needs a specific clinic context. Switch to one of your clinics in Settings to use the scanner.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

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

            // Inline undo affordance — shown only when there's a
            // checkout that can still be reversed. Tapping fires the
            // void flow and dismisses the toast; the user gets a
            // second toast confirming success/failure.
            if pendingUndo != nil {
                Button {
                    performUndo()
                } label: {
                    Text("Undo")
                        .font(AppFonts.captionSemibold)
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().stroke(AppColors.accent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
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
        guard let clinicID = authManager.effectiveClinicID else { return }

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
                // Skip the intermediate ScanResultView "found" screen
                // entirely — it auto-advanced after 1.5s anyway and
                // gave the user no useful interaction in that time.
                // Just push to ItemDetail and show a brief toast so
                // they have visual confirmation the scan worked.
                itemForDetail = item
                showToast("Found · \(item.name)")
                return
            }
        } catch {
            print("[ScanTab] inventory lookup error: \(error)")
        }

        let catalogResult = await searchService.lookupBarcode(scannedValue)
        switch catalogResult {
        case .found(let catalogItem, let gtin, let parsed):
            #if DEBUG
            print("[ScanTab] matched catalog: \(catalogItem.hcpcsCode)")
            #endif
            scanResult = .catalogOnly(catalogItem, gtin: gtin, parsed: parsed)

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
    // MARK: - Result actions
    // ══════════════════════════════════════════════════════

    private func handleCheckOut(result: ScanOutcome) {
        guard case .itemInStock(let item) = result else { return }
        // Dead code path: in-stock scans now skip the result screen
        // and push directly to ItemDetail. Kept defensively in case
        // something else triggers .itemInStock in the future.
        itemForCheckout = item
    }

    private func handleViewDetails(result: ScanOutcome) {
        guard case .itemInStock(let item) = result else { return }
        scanResult = nil
        itemForDetail = item
    }

    private func handleAddToInventory(result: ScanOutcome) {
        scanResult = nil

        switch result {
        case .catalogOnly(let catalog, let gtin, let parsed):
            addItemPrefill = AddItemPrefill(
                name: catalog.displayName,
                hcpcsCode: catalog.hcpcsCode,
                barcode: gtin ?? "",
                category: catalog.category,
                lotNumber: parsed?.lotNumber
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
        guard case .unmatchedGTIN(let gtin, let parsed) = result else { return }
        scanResult = nil
        // Store both the GTIN (for the catalog to link) and the
        // parsed barcode (for prefill after linking). The single
        // GS1 scan we already did has the lot number; we don't want
        // the user to have to scan again just to populate AddItemView.
        pendingLinkContext = PendingLinkContext(gtin: gtin, parsed: parsed)
    }

    private func handleLinkComplete(
        gtin: String,
        item: HCPCSCatalogItem,
        context: PendingLinkContext
    ) {
        // Linking sheet auto-dismisses when we clear pendingLinkContext.
        pendingLinkContext = nil

        // Now seamlessly open AddItemView with everything from the
        // original scan PLUS the just-linked catalog data. This is
        // the key step that turns a multi-scan workflow into one:
        // the user scanned once at the top, and now lands in
        // AddItemView with name/HCPCS/category/barcode/lot all set
        // — they only need to confirm quantity and save.
        addItemPrefill = AddItemPrefill(
            name: item.displayName,
            hcpcsCode: item.hcpcsCode,
            barcode: gtin,
            category: item.category,
            lotNumber: context.parsed?.lotNumber
        )

        showToast("Linked \(gtin) → \(item.displayName)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Checkout
    // ══════════════════════════════════════════════════════

    private func performCheckout(item: InventoryItem, quantity: Int) {
        guard let user = authManager.currentUser,
              let itemID = item.id else { return }

        let clinicID = authManager.effectiveClinicID

        Task {
            do {
                try await inventoryManager.checkOut(
                    itemID: itemID,
                    amount: quantity,
                    by: user,
                    clinicID: clinicID
                )
                scanResult = nil
                pendingUndo = UndoableCheckout(
                    itemID: itemID,
                    itemName: item.name,
                    quantity: quantity,
                    timestamp: Date()
                )
                showToast(
                    "Checked out \(quantity) · \(item.name)",
                    duration: 10
                )
            } catch {
                showToast("Error: \(error.localizedDescription)")
            }
        }
    }

    /// Show a toast for `duration` seconds (default 3). When the
    /// toast dismisses, any pending undo state is also cleared so
    /// the toast doesn't reappear with stale info on a later message.
    private func showToast(_ message: String, duration: TimeInterval = 3) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            toastMessage = nil
            pendingUndo = nil
        }
    }

    /// Reverse the most recent checkout. Called from the inline Undo
    /// button in the toast. We use the recorded itemID/quantity rather
    /// than scanning history because:
    ///   - We KNOW exactly what was checked out (no ambiguity vs. a
    ///     parallel checkout from another user)
    ///   - We avoid an extra DB read just to find the log we just wrote
    ///   - The 5-min permission window is checked against `timestamp`
    ///     in the closure below
    private func performUndo() {
        guard let undo = pendingUndo,
              let user = authManager.currentUser else { return }

        let clinicID = authManager.effectiveClinicID

        // Cancel the auto-dismiss timer so the toast doesn't fade
        // mid-undo. We'll show a confirmation toast when the void
        // completes either way.
        toastTask?.cancel()
        pendingUndo = nil

        Task {
            do {
                try await inventoryManager.voidCheckout(
                    itemID: undo.itemID,
                    amount: undo.quantity,
                    checkoutTime: undo.timestamp,
                    by: user,
                    clinicID: clinicID
                )
                showToast("Undone · \(undo.itemName)")
            } catch {
                showToast("Couldn't undo: \(error.localizedDescription)")
            }
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
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ScanTabView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(HCPCSSearchService())
}
