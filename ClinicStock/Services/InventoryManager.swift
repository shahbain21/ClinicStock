//
//  InventoryManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  Updated to use subcollection path:
//  inventory/{clinicID}/items/{itemID}
//

import Foundation
import Combine
import FirebaseFirestore

class InventoryManager: ObservableObject {

    @Published var items: [InventoryItem] = []
    @Published var lowStockItems: [InventoryItem] = []
    @Published var recentLogs: [HistoryLog] = []
    @Published var isLoading = false

    private let dbService = DatabaseService.shared
    private var inventoryListener: ListenerRegistration?
    private var logsListener: ListenerRegistration?

    // Store clinicID so all operations know which clinic to touch
    private var currentClinicID: String?

    deinit {
        stopListening()
    }

    // ── Start listening to a clinic's data ──
    func startListening(clinicID: String) {
        stopListening()
        currentClinicID = clinicID
        isLoading = true

        inventoryListener = dbService.listenToInventory(
            clinicID: clinicID
        ) { [weak self] items in
            DispatchQueue.main.async {
                self?.items = items
                self?.lowStockItems = items.filter { $0.isLowStock }
                self?.isLoading = false
            }
        }

        logsListener = dbService.listenToRecentLogs(
            clinicID: clinicID
        ) { [weak self] logs in
            DispatchQueue.main.async {
                self?.recentLogs = logs
            }
        }

        print("Listening to clinic: \(clinicID)")
    }

    // ── Stop listening ──
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

        guard let clinicID = user.clinicID.isEmpty ? nil : user.clinicID else {
            throw AppError.itemNotFound
        }

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
        guard PermissionManager.canVoidOwnCheckout(
            role: user.role,
            checkoutTime: checkoutTime
        ) else {
            throw AppError.voidWindowExpired
        }

        let clinicID = user.clinicID

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

        let clinicID = user.clinicID

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

        let clinicID = user.clinicID

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
        by user: AppUser
    ) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = user.clinicID

        if !barcode.isEmpty {
            let exists = try await dbService.barcodeExists(
                barcode: barcode,
                clinicID: clinicID
            )
            if exists { throw AppError.duplicateBarcode }
        }

        let itemID = try await dbService.addItem([
            "name": name,
            "hcpcsCode": hcpcsCode,
            "lotNumber": lotNumber,
            "size": size,
            "barcode": barcode,
            "quantity": quantity,
            "originalQuantity": quantity,
            "lowStockThreshold": lowStockThreshold,
            "clinicID": clinicID,
            "category": category,
            "manufacturer": manufacturer,
            "unitCost": 0,
            "lastUpdatedBy": user.id ?? "",
            "lastUpdated": Timestamp(date: Date()),
            "dateAdded": Timestamp(date: Date()),
            "notes": notes
        ], clinicID: clinicID)

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": name,
            "itemBarcode": barcode,
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

        let clinicID = user.clinicID

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
            barcode: barcode,
            clinicID: clinicID
        )
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
            }
        }
    }
}
