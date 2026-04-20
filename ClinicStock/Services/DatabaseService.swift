//
//  DatabaseService.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  Refactored to use subcollections:
//  inventory/{clinicID}/items/{itemID}
//  historyLogs/{clinicID}/entries/{logID}
//
//  clinicID is kept on each document AND in the path.
//  Redundant by design — easier debugging, no future bugs.
//
//  FIXES:
//  - Listener callbacks now surface errors so the UI can distinguish
//    "connection lost" from "empty inventory" — critical for medical apps.
//  - addLog() now takes clinicID as a first-class parameter and writes
//    to a clinic-scoped subcollection (historyLogs/{clinicID}/entries).
//    Callers no longer need to remember to put clinicID in the dict.
//  - getLowStockItems flagged with TODO for eventual server-side filtering.
//  - getClinic now defaults to active-only, with includeInactive: option
//    for admin tools that need to see deactivated clinics.
//  - Minor cleanups (redundant `let _`).
//

import Foundation
import Combine
import FirebaseFirestore

class DatabaseService {

    // Singleton — one instance shared across the app
    static let shared = DatabaseService()

    private let db = Firestore.firestore()

    private init() {
        print("DatabaseService initialized")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - INVENTORY
    // Path: inventory/{clinicID}/items/{itemID}
    // ══════════════════════════════════════════════════════

    // Convenience — returns the items subcollection for a clinic
    private func itemsCollection(clinicID: String) -> CollectionReference {
        return db.collection("inventory")
            .document(clinicID)
            .collection("items")
    }

    // ── Listen to inventory in real time ──
    //
    // The completion handler receives ([InventoryItem], Error?) so callers
    // can distinguish "query succeeded, no items" from "listener failed".
    //
    func listenToInventory(
        clinicID: String,
        completion: @escaping ([InventoryItem], Error?) -> Void
    ) -> ListenerRegistration {

        return itemsCollection(clinicID: clinicID)
            .order(by: "name")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Inventory listener error: \(error)")
                    completion([], error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion([], nil)
                    return
                }

                let items = documents.compactMap {
                    try? $0.data(as: InventoryItem.self)
                }

                print("Loaded \(items.count) inventory items for clinic \(clinicID)")
                completion(items, nil)
            }
    }

    // ── Get a single item ──
    func getItem(itemID: String, clinicID: String) async throws -> InventoryItem? {
        let doc = try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .getDocument()
        return try? doc.data(as: InventoryItem.self)
    }

    // ── Find item by barcode ──
    func findByBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", isEqualTo: barcode)
            .limit(to: 1)
            .getDocuments()

        return try? snapshot.documents.first?.data(as: InventoryItem.self)
    }

    // ── Check if barcode already exists ──
    func barcodeExists(barcode: String, clinicID: String) async throws -> Bool {
        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", isEqualTo: barcode)
            .limit(to: 1)
            .getDocuments()

        return !snapshot.documents.isEmpty
    }

    // ── Add a new item ──
    func addItem(_ item: [String: Any], clinicID: String) async throws -> String {
        let docRef = try await itemsCollection(clinicID: clinicID)
            .addDocument(data: item)
        print("Added item: \(docRef.documentID) to clinic \(clinicID)")
        return docRef.documentID
    }

    // ── Update an item ──
    func updateItem(itemID: String, clinicID: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["lastUpdated"] = Timestamp(date: Date())

        try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .updateData(updateData)
        print("Updated item: \(itemID)")
    }

    // ── Delete an item ──
    func deleteItem(itemID: String, clinicID: String) async throws {
        try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .delete()
        print("Deleted item: \(itemID)")
    }

    // ── Get low stock items for a clinic ──
    //
    // TODO: Client-side filtering — fine for ~100 items per clinic, but at
    // scale we should denormalize an `isLowStock: Bool` field updated on
    // every quantity change so we can query `.whereField("isLowStock", ...)`.
    // Firestore can't compare two fields against each other in a query.
    //
    func getLowStockItems(clinicID: String) async throws -> [InventoryItem] {
        let snapshot = try await itemsCollection(clinicID: clinicID)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: InventoryItem.self)
        }.filter { $0.isLowStock }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - HCPCS CATALOG
    // Path: hcpcsCatalog/{hcpcsCode}
    // Global — shared across all clinics
    // ══════════════════════════════════════════════════════

    // ── Get a single catalog item by HCPCS code ──
    func getCatalogItem(code: String) async throws -> HCPCSCatalogItem? {
        let doc = try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .getDocument()
        return try? doc.data(as: HCPCSCatalogItem.self)
    }

    // ── Search catalog by common name (exact match against commonNames array) ──
    //
    // Note: This is an EXACT match via arrayContains — "knee brace" in the
    // array won't match a search for "knee". HCPCSSearchService does smarter
    // substring matching client-side after loading the full catalog via
    // getAllCatalogItems(). This method is kept for future admin tooling
    // (e.g. "find items tagged exactly 'tens unit'").
    //
    func searchCatalog(query: String) async throws -> [HCPCSCatalogItem] {
        let snapshot = try await db.collection("hcpcsCatalog")
            .whereField("commonNames", arrayContains: query.lowercased())
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HCPCSCatalogItem.self)
        }
    }

    // ── Search catalog by category ──
    func getCatalogByCategory(category: String) async throws -> [HCPCSCatalogItem] {
        let snapshot = try await db.collection("hcpcsCatalog")
            .whereField("category", isEqualTo: category)
            .whereField("isActive", isEqualTo: true)
            .order(by: "hcpcsCode")
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HCPCSCatalogItem.self)
        }
    }

    // ── Search catalog by GTIN ──
    func getCatalogItemByGTIN(gtin: String) async throws -> HCPCSCatalogItem? {
        let snapshot = try await db.collection("hcpcsCatalog")
            .whereField("gtins", arrayContains: gtin)
            .limit(to: 1)
            .getDocuments()

        return try? snapshot.documents.first?.data(as: HCPCSCatalogItem.self)
    }

    // ── Get ALL catalog items (used by HCPCSSearchService for local cache) ──
    func getAllCatalogItems() async throws -> [HCPCSCatalogItem] {
        let snapshot = try await db.collection("hcpcsCatalog")
            .order(by: "hcpcsCode")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: HCPCSCatalogItem.self)
        }
    }

    // ── Add GTIN to catalog item ──
    func addGTINToCatalog(code: String, gtin: String) async throws {
        try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .updateData(["gtins": FieldValue.arrayUnion([gtin])])
    }

    // ── Add common name to catalog item ──
    func addCommonNameToCatalog(code: String, name: String) async throws {
        try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .updateData(["commonNames": FieldValue.arrayUnion([name.lowercased()])])
    }

    // ── Save a new catalog item (from NLM fallback) ──
    func saveCatalogItem(_ item: [String: Any]) async throws {
        guard let code = item["hcpcsCode"] as? String else { return }
        try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .setData(item, merge: true)
        print("Catalog item saved: \(code)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - HISTORY LOGS
    // Path: historyLogs/{clinicID}/entries/{logID}
    //
    // Subcollection by clinic — avoids a whereField filter on every read
    // and makes clinicID mandatory at the API level instead of hoping the
    // caller remembered to put it in the dict.
    // ══════════════════════════════════════════════════════

    // Convenience — returns the entries subcollection for a clinic
    private func logsCollection(clinicID: String) -> CollectionReference {
        return db.collection("historyLogs")
            .document(clinicID)
            .collection("entries")
    }

    // ── Add a log entry ──
    //
    // clinicID is a required parameter. It's also merged into the document
    // data for redundancy (same pattern as inventory items).
    //
    func addLog(_ log: [String: Any], clinicID: String) async throws {
        var logData = log
        logData["clinicID"] = clinicID

        _ = try await logsCollection(clinicID: clinicID)
            .addDocument(data: logData)
        print("Log added to clinic \(clinicID)")
    }

    // ── Get recent logs for a clinic ──
    func getClinicLogs(clinicID: String, limit: Int = 50) async throws -> [HistoryLog] {
        let snapshot = try await logsCollection(clinicID: clinicID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }
    }

    // ── Get logs for a specific item ──
    func getItemLogs(itemID: String, clinicID: String, limit: Int = 20) async throws -> [HistoryLog] {
        let snapshot = try await logsCollection(clinicID: clinicID)
            .whereField("itemID", isEqualTo: itemID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }
    }

    // ── Listen to recent logs in real time ──
    //
    // As with listenToInventory, the completion handler receives ([HistoryLog], Error?)
    // so callers can distinguish success-empty from failure.
    //
    func listenToRecentLogs(
        clinicID: String,
        limit: Int = 20,
        completion: @escaping ([HistoryLog], Error?) -> Void
    ) -> ListenerRegistration {

        return logsCollection(clinicID: clinicID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Logs listener error: \(error)")
                    completion([], error)
                    return
                }

                guard let documents = snapshot?.documents else {
                    completion([], nil)
                    return
                }

                let logs = documents.compactMap {
                    try? $0.data(as: HistoryLog.self)
                }
                completion(logs, nil)
            }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - USERS
    // ══════════════════════════════════════════════════════

    func getUser(userID: String) async throws -> AppUser? {
        let doc = try await db.collection("users")
            .document(userID)
            .getDocument()
        return try? doc.data(as: AppUser.self)
    }

    func getClinicUsers(clinicID: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("clinicID", isEqualTo: clinicID)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: AppUser.self)
        }
    }

    func createUserProfile(uid: String, data: [String: Any]) async throws {
        try await db.collection("users")
            .document(uid)
            .setData(data)
        print("User profile created")
    }

    func updateUser(userID: String, data: [String: Any]) async throws {
        try await db.collection("users")
            .document(userID)
            .updateData(data)
        print("User updated: \(userID)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - CLINICS
    // ══════════════════════════════════════════════════════

    func getAllClinics() async throws -> [Clinic] {
        let snapshot = try await db.collection("clinics")
            .whereField("isActive", isEqualTo: true)
            .order(by: "name")
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: Clinic.self)
        }
    }

    // ── Get a specific clinic ──
    //
    // Defaults to active-only for consistency with getAllClinics().
    // Pass includeInactive: true from admin tools that need to see or
    // reactivate deactivated clinics.
    //
    func getClinic(
        clinicID: String,
        includeInactive: Bool = false
    ) async throws -> Clinic? {
        let doc = try await db.collection("clinics")
            .document(clinicID)
            .getDocument()

        guard let clinic = try? doc.data(as: Clinic.self) else { return nil }

        if !includeInactive && !clinic.isActive {
            return nil
        }
        return clinic
    }

    // ══════════════════════════════════════════════════════
    // MARK: - SETTINGS
    // ══════════════════════════════════════════════════════

    func getCategories() async throws -> [String] {
        let doc = try await db.collection("settings")
            .document("categories")
            .getDocument()
        return doc.data()?["list"] as? [String] ?? []
    }

    func getSizes() async throws -> [String] {
        let doc = try await db.collection("settings")
            .document("sizes")
            .getDocument()
        return doc.data()?["list"] as? [String] ?? []
    }
}
