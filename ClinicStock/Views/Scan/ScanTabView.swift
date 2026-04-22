//
//  ScanTabView.swift
//  ClinicStock
//
//  The Scan tab. Fast-checkout surface for staff: scan an item, confirm
//  the quantity, done. Different from the Catalog tab, which is a
//  lookup reference.
//
//  Flow:
//    1. Idle — big "Tap to scan" button. Also surfaces last action
//       confirmation ("Checked out 2 · LSO Brace").
//    2. Scanner — camera sheet. On successful read, kicks off lookup.
//    3. Looking up — brief spinner while we check inventory + catalog.
//    4. Result — ScanResultView with actions appropriate to the state.
//    5. Checkout — stepper sheet (reused from ItemDetailView).
//    6. Return to idle with confirmation toast, ready for next scan.
//

import SwiftUI

struct ScanTabView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @EnvironmentObject var searchService: HCPCSSearchService

    // Scanner / lookup state
    @State private var showScanner = false
    @State private var isLookingUp = false
    @State private var scanResult: ScanResult? = nil

    // Post-checkout confirmation toast
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    // Checkout + add-to-inventory sheet state
    @State private var itemForCheckout: InventoryItem? = nil
    @State private var catalogForAdd: HCPCSCatalogItem? = nil

    // Navigation to full item detail
    @State private var itemForDetail: InventoryItem? = nil

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

                // Toast overlay
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
            .sheet(item: $catalogForAdd) { catalog in
                // AddItemView doesn't currently accept a pre-populated
                // catalog entry, so this just opens the blank form.
                // Future: pass catalog to pre-fill name/HCPCS/category.
                AddItemView()
                    .environmentObject(authManager)
                    .environmentObject(inventoryManager)
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
    //
    // Order: inventory (clinic stock) first, catalog second. Inventory
    // is the fast path — this tab is primarily about "I'm checking out
    // something I have." Only fall through to catalog if nothing matches
    // in stock.
    // ══════════════════════════════════════════════════════

    private func lookup(scannedValue: String) async {
        guard let user = authManager.currentUser else { return }

        isLookingUp = true
        defer { isLookingUp = false }

        // 1. Try inventory first
        do {
            if let item = try await inventoryManager.lookupBarcode(
                barcode: scannedValue,
                by: user
            ) {
                scanResult = .itemInStock(item)
                return
            }
        } catch {
            print("Inventory barcode lookup error: \(error)")
            // Fall through to catalog lookup
        }

        // 2. Try catalog — either we have this SKU as a reference but
        //    not in stock, or it's completely unknown.
        let catalogResult = await searchService.lookupBarcode(scannedValue)
        switch catalogResult {
        case .found(let catalogItem, let gtin):
            scanResult = .catalogOnly(catalogItem, gtin: gtin)
        case .gtinNotFound, .unrecognized:
            scanResult = .notFound(scannedValue: scannedValue)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Result actions
    // ══════════════════════════════════════════════════════

    private func handleCheckOut(result: ScanResult) {
        guard case .itemInStock(let item) = result else { return }
        itemForCheckout = item
    }

    private func handleViewDetails(result: ScanResult) {
        guard case .itemInStock(let item) = result else { return }
        scanResult = nil
        itemForDetail = item
    }

    private func handleAddToInventory(result: ScanResult) {
        guard case .catalogOnly(let catalog, _) = result else { return }
        catalogForAdd = catalog
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
                // Success — return to idle state with a confirmation toast.
                scanResult = nil
                showToast("Checked out \(quantity) · \(item.name)")
            } catch {
                // On error, leave the result screen up so the user can see
                // what happened. Show error as a toast.
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
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ScanTabView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(HCPCSSearchService())
}
