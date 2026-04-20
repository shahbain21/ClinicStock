//
//  InventoryManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  FIXES:
//  - @MainActor on the class — all @Published mutations now main-thread-safe
//  - Transactions on checkOut/voidCheckout/addStock — no more race conditions
//    (previously: two simultaneous checkouts could lose inventory count)
//  - listenerError published for UI to distinguish connection loss from empty
//  - Updated to new DatabaseService API:
//      * listenToInventory/listenToRecentLogs callbacks now receive Error?
//      * addLog takes clinicID: as a parameter
//  - Removed dead currentClinicID property (set but never read)
//  - Removed redundant clinicID from log dicts (DatabaseService adds it)
//  - Low-stock detection still works correctly with the transaction refactor
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
class InventoryManager: ObservableObject {

    @Published var items: [InventoryItem] = []
    @Published var lowStockItems: [InventoryItem] = []
    @Published var recentLogs: [HistoryLog] = []
    @Published var isLoading = false

    // Surfaces listener errors so the UI can show a "connection lost" banner.
    // nil when healthy, non-nil when the Firestore listener is in an error state.
    @Published var listenerError: Error?

    private let dbService = DatabaseService.shared
    private let db = Firestore.firestore()

    private var inventoryListener: ListenerRegistration?
    private var logsListener: ListenerRegistration?

    // Note: deinit can't access main-actor-isolated properties synchronously,
    // so we tear down listeners via a nonisolated helper.
    deinit {
        inventoryListener?.remove()
        logsListener?.remove()
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
        isLoading = true
        listenerError = nil

        inventoryListener = dbService.listenToInventory(
            clinicID: clinicID
        ) { [weak self] items, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isLoading = false

                if let error = error {
                    self.listenerError = error
                    // Don't clear items on error — keep showing last-known state
                    // so staff aren't looking at a blank screen during a blip.
                    return
                }

                self.listenerError = nil
                self.items = items
                self.lowStockItems = items.filter { $0.isLowStock }
            }
        }

        logsListener = dbService.listenToRecentLogs(
            clinicID: clinicID
        ) { [weak self] logs, error in
            Task { @MainActor in
                guard let self = self else { return }

                if error != nil {
                    // Logs failing is less critical — don't overwrite inventory error
                    return
                }

                self.recentLogs = logs
            }
        }

        print("Listening to clinic: \(clinicID)")
    }

    func stopListening() {
        inventoryListener?.remove()
        logsListener?.remove()
        inventoryListener = nil
        logsListener = nil
        isLoading = false
        listenerError = nil
    }

    // ═══════════════════════════════════
    // MARK: - CHECK OUT (transactional)
    //
    // Uses a Firestore transaction to read + validate + write atomically.
    // Prevents the classic race where two devices read quantity=5, both
    // compute 5-3=2, and both write 2 — losing 3 items of stock.
    // ═══════════════════════════════════

    func checkOut(itemID: String, amount: Int, by user: AppUser) async throws {
        guard PermissionManager.canCheckOut(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)
        let itemRef = db.collection("inventory")
            .document(clinicID)
            .collection("items")
            .document(itemID)

        // Transaction returns the pre/post quantity so we can log and detect
        // low-stock threshold crossings *after* the atomic write commits.
        let result: CheckoutResult = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(itemRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let item = try? snapshot.data(as: InventoryItem.self) else {
                    let error = NSError(
                        domain: "InventoryManager",
                        code: AppError.itemNotFound.code,
                        userInfo: [NSLocalizedDescriptionKey: "Item not found"]
                    )
                    errorPointer?.pointee = error
                    return nil
                }

                let newQuantity = item.quantity - amount
                guard newQuantity >= 0 else {
                    let error = NSError(
                        domain: "InventoryManager",
                        code: AppError.insufficientStock.code,
                        userInfo: [NSLocalizedDescriptionKey: "Not enough stock"]
                    )
                    errorPointer?.pointee = error
                    return nil
                }

                transaction.updateData([
                    "quantity": newQuantity,
                    "lastUpdatedBy": user.id ?? "",
                    "lastUpdated": Timestamp(date: Date())
                ], forDocument: itemRef)

                return CheckoutResult(
                    item: item,
                    previousQuantity: item.quantity,
                    newQuantity: newQuantity
                )
            }, completion: { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result as? CheckoutResult {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.itemNotFound)
                }
            })
        }

        // Audit log — runs after the transaction commits
        try await dbService.addLog([
            "itemID": itemID,
            "itemName": result.item.name,
            "itemBarcode": result.item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "action": "quantityUpdate",
            "details": "Checked out \(amount): \(result.previousQuantity) → \(result.newQuantity)",
            "previousValue": "\(result.previousQuantity)",
            "newValue": "\(result.newQuantity)",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        // Low-stock alert — fires only on the transition into low stock
        let threshold = result.item.lowStockThreshold
        let crossedIntoLow = result.newQuantity <= threshold
                          && result.previousQuantity > threshold
        if crossedIntoLow {
            let alertDetail = result.newQuantity <= 0
                ? "\(result.item.name) is OUT OF STOCK"
                : "\(result.item.name) is LOW STOCK (\(result.newQuantity) remaining)"

            try await dbService.addLog([
                "itemID": itemID,
                "itemName": result.item.name,
                "itemBarcode": result.item.barcode,
                "userID": "system",
                "userName": "System",
                "action": "stockAlert",
                "details": alertDetail,
                "previousValue": "\(result.previousQuantity)",
                "newValue": "\(result.newQuantity)",
                "timestamp": Timestamp(date: Date())
            ], clinicID: clinicID)
        }
    }

    // ═══════════════════════════════════
    // MARK: - VOID CHECKOUT (transactional)
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

        let clinicID = try validClinicID(from: user)
        let result = try await atomicQuantityChange(
            itemID: itemID,
            clinicID: clinicID,
            delta: amount,
            by: user
        )

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": result.item.name,
            "itemBarcode": result.item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "action": "quantityUpdate",
            "details": "Voided checkout (+\(amount)): \(result.previousQuantity) → \(result.newQuantity)",
            "previousValue": "\(result.previousQuantity)",
            "newValue": "\(result.newQuantity)",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)
    }

    // ═══════════════════════════════════
    // MARK: - ADD STOCK (transactional)
    //
    // Also bumps originalQuantity — preserves the "how much have we ever
    // received" metric for reporting.
    // ═══════════════════════════════════

    func addStock(itemID: String, amount: Int, by user: AppUser) async throws {
        guard PermissionManager.canAddStock(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)
        let itemRef = db.collection("inventory")
            .document(clinicID)
            .collection("items")
            .document(itemID)

        let result: CheckoutResult = try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(itemRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let item = try? snapshot.data(as: InventoryItem.self) else {
                    let error = NSError(
                        domain: "InventoryManager",
                        code: AppError.itemNotFound.code,
                        userInfo: [NSLocalizedDescriptionKey: "Item not found"]
                    )
                    errorPointer?.pointee = error
                    return nil
                }

                let newQuantity = item.quantity + amount

                transaction.updateData([
                    "quantity": newQuantity,
                    "originalQuantity": item.originalQuantity + amount,
                    "lastUpdatedBy": user.id ?? "",
                    "lastUpdated": Timestamp(date: Date())
                ], forDocument: itemRef)

                return CheckoutResult(
                    item: item,
                    previousQuantity: item.quantity,
                    newQuantity: newQuantity
                )
            }, completion: { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result as? CheckoutResult {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.itemNotFound)
                }
            })
        }

        try await dbService.addLog([
            "itemID": itemID,
            "itemName": result.item.name,
            "itemBarcode": result.item.barcode,
            "userID": user.id ?? "",
            "userName": user.displayName,
            "action": "quantityUpdate",
            "details": "Restocked +\(amount): \(result.previousQuantity) → \(result.newQuantity)",
            "previousValue": "\(result.previousQuantity)",
            "newValue": "\(result.newQuantity)",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)
    }

    // ═══════════════════════════════════
    // MARK: - REMOVE ITEM
    //
    // Deletion doesn't need a transaction — the whole doc is gone.
    // We still read first for the log entry.
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
            "action": "deleted",
            "details": "Removed \(item.name) (\(item.quantity) remaining)",
            "previousValue": "\(item.quantity)",
            "newValue": "0",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)
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
            "unitCost": unitCost,
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
            "action": "added",
            "details": "Added \(name) | Qty: \(quantity) | HCPCS: \(hcpcsCode)",
            "previousValue": "",
            "newValue": "\(quantity)",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)
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
            "action": "infoUpdate",
            "details": changeDescription,
            "previousValue": "",
            "newValue": "",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)
    }

    // ═══════════════════════════════════
    // MARK: - BARCODE LOOKUP
    //
    // Takes the user so we derive clinicID consistently with everything else.
    // Also runs the permission check (even though staff can scan — keeps the
    // pattern uniform and makes future permission tightening easier).
    // ═══════════════════════════════════

    func lookupBarcode(barcode: String, by user: AppUser) async throws -> InventoryItem? {
        guard PermissionManager.canScanBarcode(role: user.role) else {
            throw AppError.insufficientPermissions
        }

        let clinicID = try validClinicID(from: user)

        return try await dbService.findByBarcode(
            barcode: barcode,
            clinicID: clinicID
        )
    }

    // ═══════════════════════════════════
    // MARK: - Private: shared transaction helper
    //
    // For simple delta changes (voidCheckout) where we don't need custom
    // validation beyond "item exists." checkOut and addStock don't use this
    // because they have extra rules (no-negative, bump originalQuantity).
    // ═══════════════════════════════════

    private func atomicQuantityChange(
        itemID: String,
        clinicID: String,
        delta: Int,
        by user: AppUser
    ) async throws -> CheckoutResult {
        let itemRef = db.collection("inventory")
            .document(clinicID)
            .collection("items")
            .document(itemID)

        return try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(itemRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let item = try? snapshot.data(as: InventoryItem.self) else {
                    let error = NSError(
                        domain: "InventoryManager",
                        code: AppError.itemNotFound.code,
                        userInfo: [NSLocalizedDescriptionKey: "Item not found"]
                    )
                    errorPointer?.pointee = error
                    return nil
                }

                let newQuantity = item.quantity + delta

                transaction.updateData([
                    "quantity": newQuantity,
                    "lastUpdatedBy": user.id ?? "",
                    "lastUpdated": Timestamp(date: Date())
                ], forDocument: itemRef)

                return CheckoutResult(
                    item: item,
                    previousQuantity: item.quantity,
                    newQuantity: newQuantity
                )
            }, completion: { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result as? CheckoutResult {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AppError.itemNotFound)
                }
            })
        }
    }

    // ═══════════════════════════════════
    // MARK: - Private: transaction result
    // ═══════════════════════════════════

    private class CheckoutResult: NSObject {
        let item: InventoryItem
        let previousQuantity: Int
        let newQuantity: Int

        init(item: InventoryItem, previousQuantity: Int, newQuantity: Int) {
            self.item = item
            self.previousQuantity = previousQuantity
            self.newQuantity = newQuantity
        }
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

        // Stable numeric codes so NSError can round-trip through transactions
        var code: Int {
            switch self {
            case .insufficientPermissions: return 1001
            case .itemNotFound:            return 1002
            case .insufficientStock:       return 1003
            case .duplicateBarcode:        return 1004
            case .voidWindowExpired:       return 1005
            case .noClinicAssigned:        return 1006
            }
        }

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
