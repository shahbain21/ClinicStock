//
//  InventoryManager.swift
//  ClinicStock
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
    private var aggregateCache: [InventoryItem]?
    private var currentClinicID: String?

    deinit { stopListening() }

    // MARK: - Clinic ID Validation

    //Returns the clinic ID to use for a write operation.
    // Uses the override if provided, otherwise falls back to the user's own clinicID.
    private func validClinicID(from user: AppUser, override: String? = nil) throws -> String {
        if let override, !override.isEmpty { return override }
        if let id = user.clinicID, !id.isEmpty { return id }
        throw AppError.noClinicAssigned
    }

    // MARK: - Listeners

    func startListening(clinicID: String) {
        stopListening()
        currentClinicID = clinicID
        isLoading = true

        inventoryListener = dbService.listenToInventory(clinicID: clinicID) { [weak self] items, error in
            DispatchQueue.main.async {
                self?.listenerError = error
                self?.items = items
                self?.lowStockItems = items.filter { $0.isLowStock }
                self?.isLoading = false
            }
        }

        logsListener = dbService.listenToRecentLogs(clinicID: clinicID) { [weak self] logs, error in
            DispatchQueue.main.async {
                self?.recentLogs = logs
            }
        }
    }

    func stopListening() {
        inventoryListener?.remove()
        logsListener?.remove()
        inventoryListener = nil
        logsListener = nil
        currentClinicID = nil
        isLoading = false
    }

    func clearForSignOut() {
        stopListening()
        items = []
        lowStockItems = []
        recentLogs = []
        aggregateCache = nil
        listenerError = nil
    }

    // MARK: - Aggregate Inventory

    //Loads inventory across all clinics for platform admin.
    // Shows cached data immediately if available, then refreshes in the background.
    func loadAggregateInventory() async {
        stopListening()

        if let cached = aggregateCache {
            await MainActor.run {
                self.items = cached
                self.lowStockItems = cached.filter { $0.isLowStock }
                self.recentLogs = []
                self.isLoading = false
            }
        } else {
            await MainActor.run { self.isLoading = true }
        }

        do {
            let allItems = try await dbService.getAllInventoryAcrossClinics()
            await MainActor.run {
                self.items = allItems
                self.lowStockItems = allItems.filter { $0.isLowStock }
                self.recentLogs = []
                self.isLoading = false
                self.listenerError = nil
                self.aggregateCache = allItems
            }
        } catch {
            await MainActor.run {
                self.listenerError = error
                self.isLoading = false
            }
        }
    }

    // MARK: - Check Out

    func checkOut(itemID: String, amount: Int, by user: AppUser, clinicID: String? = nil) async throws {
        guard PermissionManager.canCheckOut(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        guard let item = try await dbService.getItem(itemID: itemID, clinicID: clinicID) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity - amount
        guard newQuantity >= 0 else { throw AppError.insufficientStock }

        try await dbService.updateItem(itemID: itemID, clinicID: clinicID, data: [
            "quantity": newQuantity,
            "lastUpdatedBy": user.id ?? ""
        ])

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      item.name,
            "itemBarcode":   item.barcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "quantityUpdate",
            "updateType":    "checkout",
            "details":       "Checked out \(amount): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue":      "\(newQuantity)",
            "timestamp":     Timestamp(date: Date())
        ])

        if newQuantity <= item.lowStockThreshold && item.quantity > item.lowStockThreshold {
            try await dbService.addLog([
                "itemID":        itemID,
                "itemName":      item.name,
                "itemBarcode":   item.barcode,
                "userID":        "system",
                "userName":      "System",
                "clinicID":      clinicID,
                "action":        "stockAlert",
                "details":       "\(item.name) is LOW STOCK (\(newQuantity) remaining)",
                "previousValue": "\(item.quantity)",
                "newValue":      "\(newQuantity)",
                "timestamp":     Timestamp(date: Date())
            ])
        }
    }

    // MARK: - Void Checkout

    func voidCheckout(itemID: String, amount: Int, checkoutTime: Date, by user: AppUser, clinicID: String? = nil) async throws {
        guard PermissionManager.canVoidRecentCheckout(role: user.role, checkoutTime: checkoutTime) else {
            throw AppError.voidWindowExpired
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        guard let item = try await dbService.getItem(itemID: itemID, clinicID: clinicID) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity + amount

        try await dbService.updateItem(itemID: itemID, clinicID: clinicID, data: [
            "quantity": newQuantity,
            "lastUpdatedBy": user.id ?? ""
        ])

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      item.name,
            "itemBarcode":   item.barcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "quantityUpdate",
            "updateType":    "restock",
            "details":       "Voided checkout (+\(amount)): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue":      "\(newQuantity)",
            "timestamp":     Timestamp(date: Date())
        ])
    }

    // MARK: - Add Stock

    func addStock(itemID: String, amount: Int, by user: AppUser, clinicID: String? = nil) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        guard let item = try await dbService.getItem(itemID: itemID, clinicID: clinicID) else {
            throw AppError.itemNotFound
        }

        let newQuantity = item.quantity + amount

        try await dbService.updateItem(itemID: itemID, clinicID: clinicID, data: [
            "quantity": newQuantity,
            "lastUpdatedBy": user.id ?? ""
        ])

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      item.name,
            "itemBarcode":   item.barcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "quantityUpdate",
            "updateType":    "restock",
            "details":       "Restocked +\(amount): \(item.quantity) → \(newQuantity)",
            "previousValue": "\(item.quantity)",
            "newValue":      "\(newQuantity)",
            "timestamp":     Timestamp(date: Date())
        ])
    }

    // MARK: - Remove Item

    func removeItem(itemID: String, by user: AppUser, clinicID: String? = nil) async throws {
        guard PermissionManager.canRemoveStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        guard let item = try await dbService.getItem(itemID: itemID, clinicID: clinicID) else {
            throw AppError.itemNotFound
        }

        try await dbService.deleteItem(itemID: itemID, clinicID: clinicID)

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      item.name,
            "itemBarcode":   item.barcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "deleted",
            "details":       "Removed \(item.name) (\(item.quantity) remaining)",
            "previousValue": "\(item.quantity)",
            "newValue":      "0",
            "timestamp":     Timestamp(date: Date())
        ])
    }

    // MARK: - Add New Item

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
        by user: AppUser,
        clinicID: String? = nil
    ) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        if !barcode.isEmpty {
            let exists = try await dbService.barcodeExists(
                candidates: barcodeCandidates(for: barcode),
                clinicID: clinicID
            )
            if exists { throw AppError.duplicateBarcode }
        }

        let storedBarcode: String = {
            guard !barcode.isEmpty else { return "" }
            return BarcodeService.parse(barcode).gtin ?? barcode
        }()

        let itemID = try await dbService.addItem([
            "name":              name,
            "hcpcsCode":         hcpcsCode,
            "lotNumber":         lotNumber,
            "size":              size,
            "barcode":           storedBarcode,
            "quantity":          quantity,
            "lowStockThreshold": lowStockThreshold,
            "clinicID":          clinicID,
            "category":          category,
            "manufacturer":      manufacturer,
            "unitCost":          unitCost,
            "lastUpdatedBy":     user.id ?? "",
            "lastUpdated":       Timestamp(date: Date()),
            "dateAdded":         Timestamp(date: Date()),
            "notes":             notes
        ], clinicID: clinicID)

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      name,
            "itemBarcode":   storedBarcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "added",
            "updateType":    "restock",
            "details":       "Added \(name) | Qty: \(quantity) | HCPCS: \(hcpcsCode)",
            "previousValue": "",
            "newValue":      "\(quantity)",
            "timestamp":     Timestamp(date: Date())
        ])
    }

    // MARK: - Update Item Info

    func updateItemInfo(
        itemID: String,
        updates: [String: Any],
        changeDescription: String,
        by user: AppUser,
        clinicID: String? = nil
    ) async throws {
        guard PermissionManager.canEditItemInfo(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user, override: clinicID)

        guard let item = try await dbService.getItem(itemID: itemID, clinicID: clinicID) else {
            throw AppError.itemNotFound
        }

        var updateData = updates
        updateData["lastUpdatedBy"] = user.id ?? ""

        try await dbService.updateItem(itemID: itemID, clinicID: clinicID, data: updateData)

        try await dbService.addLog([
            "itemID":        itemID,
            "itemName":      item.name,
            "itemBarcode":   item.barcode,
            "userID":        user.id ?? "",
            "userName":      user.displayName,
            "clinicID":      clinicID,
            "action":        "infoUpdate",
            "details":       changeDescription,
            "previousValue": "",
            "newValue":      "",
            "timestamp":     Timestamp(date: Date())
        ])
    }

    // MARK: - Barcode Lookup

    func lookupBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        try await dbService.findByBarcode(candidates: barcodeCandidates(for: barcode), clinicID: clinicID)
    }

    /// Generates all barcode format variants to try during lookup.
    /// Handles mismatches between how a barcode was scanned vs how it was stored.
    private func barcodeCandidates(for raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]

        guard let gtin = BarcodeService.parse(trimmed).gtin else { return candidates }

        candidates.append(gtin)

        if gtin.count == 14 && gtin.first == "0" {
            candidates.append(String(gtin.dropFirst()))
        }
        if gtin.count == 14 && gtin.hasPrefix("00") {
            candidates.append(String(gtin.dropFirst(2)))
        }

        return candidates
    }

    // MARK: - Errors

    enum AppError: LocalizedError {
        case insufficientPermissions
        case itemNotFound
        case insufficientStock
        case duplicateBarcode
        case voidWindowExpired
        case noClinicAssigned

        var errorDescription: String? {
            switch self {
            case .insufficientPermissions: return "You don't have permission for this action."
            case .itemNotFound:            return "Item not found."
            case .insufficientStock:       return "Not enough stock."
            case .duplicateBarcode:        return "An item with this barcode already exists."
            case .voidWindowExpired:       return "The 5-minute void window has expired. Contact an editor or above."
            case .noClinicAssigned:        return "No clinic assigned to your account. Contact your admin."
            }
        }
    }
}
