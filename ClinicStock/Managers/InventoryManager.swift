//
//  InventoryManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  FIXES:
//  - Added validClinicID() helper for consistent validation
//  - Fixed checkOut clinicID guard logic
//  - All methods now validate clinicID before proceeding
//  - Added .noClinicAssigned error case
//  - Added unitCost parameter to addNewItem
//

import Foundation
import Combine
import FirebaseFirestore

class InventoryManager: ObservableObject {

    @Published var items: [InventoryItem] = []
    @Published var lowStockItems: [InventoryItem] = []
    @Published var recentLogs: [HistoryLog] = []
    @Published var isLoading = false
    @Published var listenerError: Error?

    private let dbService = DatabaseService.shared
    private var inventoryListener: ListenerRegistration?
    private var logsListener: ListenerRegistration?

    private var currentClinicID: String?

    deinit {
        stopListening()
    }

    // ═══════════════════════════════════
    // MARK: - CLINIC ID VALIDATION
    // ═══════════════════════════════════

    private func validClinicID(from user: AppUser) throws -> String {
        guard !user.clinicID.isEmpty else {
            throw AppError.noClinicAssigned
        }
        return user.clinicID
    }

    // ═══════════════════════════════════
    // MARK: - LISTENERS
    // ═══════════════════════════════════

    func startListening(clinicID: String) {
        stopListening()
        currentClinicID = clinicID
        isLoading = true

        inventoryListener = dbService.listenToInventory(
            clinicID: clinicID
        ) { [weak self] items, error in
            DispatchQueue.main.async {
                self?.listenerError = error
                if let error = error {
                    print("Inventory listener error: \(error)")
                }
                self?.items = items
                self?.lowStockItems = items.filter { $0.isLowStock }
                self?.isLoading = false
            }
        }

        logsListener = dbService.listenToRecentLogs(
            clinicID: clinicID
        ) { [weak self] logs, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Logs listener error: \(error)")
                }
                self?.recentLogs = logs
            }
        }

        print("Listening to clinic: \(clinicID)")
    }

    func stopListening() {
        inventoryListener?.remove()
        logsListener?.remove()
        inventoryListener = nil
        logsListener = nil
        currentClinicID = nil
        isLoading = false
    }

    // ═══════════════════════════════════
    // MARK: - CHECK OUT
    // ═══════════════════════════════════

    func checkOut(itemID: String, amount: Int, by user: AppUser) async throws {
        guard PermissionManager.canCheckOut(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        guard let item = try await dbService.getItem(
            itemID: itemID,
            clinicID: clinicID
        ) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity - amount
        guard newQuantity >= 0 else {
            throw AppError.insufficientStock
        }

        try await dbService.updateItem(
            itemID: itemID,
            clinicID: clinicID,
            data: [
                "quantity": newQuantity,
                "lastUpdatedBy": user.id ?? ""
            ]
        )

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": item.name,
            "itemBarcode": item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "quantityUpdate",
            "details": "Checked out \(amount): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue": "\(newQuantity)",
            "timestamp": Timestamp(date: Date())
        ])

        // Low stock alert
        if newQuantity <= item.lowStockThreshold && item.quantity > item.lowStockThreshold {
            try await dbService.addLog([
                "itemID": itemID,
                "itemName": item.name,
                "itemBarcode": item.barcode,
                "userID": "system",
                "userName": "System",
                "clinicID": clinicID,
                "action": "stockAlert",
                "details": "\(item.name) is LOW STOCK (\(newQuantity) remaining)",
                "previousValue": "\(item.quantity)",
                "newValue": "\(newQuantity)",
                "timestamp": Timestamp(date: Date())
            ])
        }
    }

    // ═══════════════════════════════════
    // MARK: - VOID CHECKOUT
    // ═══════════════════════════════════

    func voidCheckout(
        itemID: String,
        amount: Int,
        checkoutTime: Date,
        by user: AppUser
    ) async throws {
        guard PermissionManager.canVoidRecentCheckout(
            role: user.role,
            checkoutTime: checkoutTime
        ) else {
            throw AppError.voidWindowExpired
        }

        let clinicID = try validClinicID(from: user)

        guard let item = try await dbService.getItem(
            itemID: itemID,
            clinicID: clinicID
        ) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity + amount

        try await dbService.updateItem(
            itemID: itemID,
            clinicID: clinicID,
            data: [
                "quantity": newQuantity,
                "lastUpdatedBy": user.id ?? ""
            ]
        )

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": item.name,
            "itemBarcode": item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "quantityUpdate",
            "details": "Voided checkout (+\(amount)): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue": "\(newQuantity)",
            "timestamp": Timestamp(date: Date())
        ])
    }

    // ═══════════════════════════════════
    // MARK: - ADD STOCK
    // ═══════════════════════════════════

    func addStock(itemID: String, amount: Int, by user: AppUser) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        guard let item = try await dbService.getItem(
            itemID: itemID,
            clinicID: clinicID
        ) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity + amount

        try await dbService.updateItem(
            itemID: itemID,
            clinicID: clinicID,
            data: [
                "quantity": newQuantity,
                "originalQuantity": item.originalQuantity + amount,
                "lastUpdatedBy": user.id ?? ""
            ]
        )

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": item.name,
            "itemBarcode": item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "quantityUpdate",
            "details": "Restocked +\(amount): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue": "\(newQuantity)",
            "timestamp": Timestamp(date: Date())
        ])
    }

    // ═══════════════════════════════════
    // MARK: - REMOVE ITEM
    // ═══════════════════════════════════

    func removeItem(itemID: String, by user: AppUser) async throws {
        guard PermissionManager.canRemoveStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        guard let item = try await dbService.getItem(
            itemID: itemID,
            clinicID: clinicID
        ) else {
            throw AppError.itemNotFound
        }

        try await dbService.deleteItem(itemID: itemID, clinicID: clinicID)

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": item.name,
            "itemBarcode": item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "deleted",
            "details": "Removed \(item.name) (\(item.quantity) remaining)",
            "previousValue": "\(item.quantity)",
            "newValue": "0",
            "timestamp": Timestamp(date: Date())
        ])
    }

    // ═══════════════════════════════════
    // MARK: - ADD NEW ITEM
    // ═══════════════════════════════════

    func addNewItem(
        name: String,
        hcpcsCode: String,
        lotNumber: String,
        size: String,
        barcode: String,
        quantity: Int,
        lowStockThreshold: Int,
        category: String,
        manufacturer: String,
        notes: String,
        unitCost: Double = 0,
        by user: AppUser
    ) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        if !barcode.isEmpty {
            // Use the same candidate expansion as lookup so duplicate
            // detection and barcode matching stay in sync. Without this,
            // scanning would say "not in stock" while adding would say
            // "duplicate" — contradictory results from the same barcode.
            let exists = try await dbService.barcodeExists(
                candidates: barcodeCandidates(for: barcode),
                clinicID: clinicID
            )
            if exists { throw AppError.duplicateBarcode }
        }

        // Normalize the barcode to its canonical 14-digit GTIN form
        // when possible, so future lookups (which also normalize) match
        // consistently. Items from before this change stored whatever
        // the user typed — that's why lookup uses candidate expansion.
        let storedBarcode: String = {
            if barcode.isEmpty { return "" }
            let parsed = BarcodeService.parse(barcode)
            return parsed.gtin ?? barcode
        }()

        let itemID = try await dbService.addItem([
            "name": name,
            "hcpcsCode": hcpcsCode,
            "lotNumber": lotNumber,
            "size": size,
            "barcode": storedBarcode,
            "quantity": quantity,
            "originalQuantity": quantity,
            "lowStockThreshold": lowStockThreshold,
            "clinicID": clinicID,
            "category": category,
            "manufacturer": manufacturer,
            "unitCost": unitCost,
            "lastUpdatedBy": user.id ?? "",
            "lastUpdated": Timestamp(date: Date()),
            "dateAdded": Timestamp(date: Date()),
            "notes": notes
        ], clinicID: clinicID)

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": name,
            "itemBarcode": storedBarcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "added",
            "details": "Added \(name) | Qty: \(quantity) | HCPCS: \(hcpcsCode)",
            "previousValue": "",
            "newValue": "\(quantity)",
            "timestamp": Timestamp(date: Date())
        ])
    }

    // ═══════════════════════════════════
    // MARK: - UPDATE ITEM INFO
    // ═══════════════════════════════════

    func updateItemInfo(
        itemID: String,
        updates: [String: Any],
        changeDescription: String,
        by user: AppUser
    ) async throws {
        guard PermissionManager.canEditItemInfo(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        guard let item = try await dbService.getItem(
            itemID: itemID,
            clinicID: clinicID
        ) else {
            throw AppError.itemNotFound
        }

        var updateData = updates
        updateData["lastUpdatedBy"] = user.id ?? ""

        try await dbService.updateItem(
            itemID: itemID,
            clinicID: clinicID,
            data: updateData
        )

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": item.name,
            "itemBarcode": item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "clinicID": clinicID,
            "action": "infoUpdate",
            "details": changeDescription,
            "previousValue": "",
            "newValue": "",
            "timestamp": Timestamp(date: Date())
        ])
    }

    // ═══════════════════════════════════
    // MARK: - BARCODE LOOKUP
    // ═══════════════════════════════════

    func lookupBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        return try await dbService.findByBarcode(
            candidates: barcodeCandidates(for: barcode),
            clinicID: clinicID
        )
    }

    /// Build the list of barcode format variants to try when looking up
    /// an item. Covers the common mismatches:
    ///  - Scanner returns 13-digit EAN-13, item stored as 14-digit GTIN
    ///  - Scanner returns 14-digit GTIN-14, item stored raw from typing
    ///  - Scanner returns GS1-128 with AIs, item stored as just the GTIN
    ///  - Raw scanned string (exact match path — preserve legacy behavior)
    ///
    /// Deduplication happens at the DatabaseService layer.
    private func barcodeCandidates(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]

        let parsed = BarcodeService.parse(trimmed)
        if let gtin = parsed.gtin {
            // 14-digit normalized form
            candidates.append(gtin)

            // 13-digit form (strip one leading zero if GTIN is 14 digits
            // starting with 0 — i.e. the EAN-13 representation)
            if gtin.count == 14 && gtin.first == "0" {
                candidates.append(String(gtin.dropFirst()))
            }

            // 12-digit form (strip two leading zeros if present — UPC-A)
            if gtin.count == 14 && gtin.hasPrefix("00") {
                candidates.append(String(gtin.dropFirst(2)))
            }
        }

        return candidates
    }

    // ═══════════════════════════════════
    // MARK: - ERRORS
    // ═══════════════════════════════════

    enum AppError: LocalizedError {
        case insufficientPermissions
        case itemNotFound
        case insufficientStock
        case duplicateBarcode
        case voidWindowExpired
        case noClinicAssigned

        var errorDescription: String? {
            switch self {
            case .insufficientPermissions:
                return "You don't have permission for this action."
            case .itemNotFound:
                return "Item not found."
            case .insufficientStock:
                return "Not enough stock."
            case .duplicateBarcode:
                return "An item with this barcode already exists."
            case .voidWindowExpired:
                return "The 5-minute void window has expired. Contact an editor or above."
            case .noClinicAssigned:
                return "No clinic assigned to your account. Contact your admin."
            }
        }
    }
}
