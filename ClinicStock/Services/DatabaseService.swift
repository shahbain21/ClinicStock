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
//  clinicID is kept on each document AND in the path. Redundant by
//  design — easier debugging, no future bugs.
//
//  RECENT ADDITIONS:
//  - getDeactivatedClinicUsers for the User Management "Show deactivated"
//    toggle.
//  - Invitation helpers: getInvitation, getPendingInvitations,
//    saveInvitation, deleteInvitation.
//
//  PRIOR FIXES:
//  - Listener callbacks surface errors so UI can distinguish connection
//    loss from empty inventory.
//  - addLog takes clinicID as a first-class parameter.
//  - getLowStockItems flagged with TODO for server-side filtering.
//  - getClinic defaults to active-only with includeInactive: opt-out.
//

import Foundation
import Combine
import FirebaseFirestore

class DatabaseService {

    static let shared = DatabaseService()

    private let db = Firestore.firestore()

    private init() {
        print("DatabaseService initialized")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - INVENTORY
    // Path: inventory/{clinicID}/items/{itemID}
    // ══════════════════════════════════════════════════════

    private func itemsCollection(clinicID: String) -> CollectionReference {
        return db.collection("inventory")
            .document(clinicID)
            .collection("items")
    }

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

    func getItem(itemID: String, clinicID: String) async throws -> InventoryItem? {
        let doc = try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .getDocument()
        return try? doc.data(as: InventoryItem.self)
    }

    func findByBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", isEqualTo: barcode)
            .limit(to: 1)
            .getDocuments()

        return try? snapshot.documents.first?.data(as: InventoryItem.self)
    }

    func barcodeExists(barcode: String, clinicID: String) async throws -> Bool {
        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", isEqualTo: barcode)
            .limit(to: 1)
            .getDocuments()

        return !snapshot.documents.isEmpty
    }

    func addItem(_ item: [String: Any], clinicID: String) async throws -> String {
        let docRef = try await itemsCollection(clinicID: clinicID)
            .addDocument(data: item)
        print("Added item: \(docRef.documentID) to clinic \(clinicID)")
        return docRef.documentID
    }

    func updateItem(itemID: String, clinicID: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["lastUpdated"] = Timestamp(date: Date())

        try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .updateData(updateData)
        print("Updated item: \(itemID)")
    }

    func deleteItem(itemID: String, clinicID: String) async throws {
        try await itemsCollection(clinicID: clinicID)
            .document(itemID)
            .delete()
        print("Deleted item: \(itemID)")
    }

    // TODO: Client-side filtering — fine for ~100 items per clinic, but
    // at scale denormalize an `isLowStock: Bool` field updated on every
    // quantity change so we can query .whereField("isLowStock", ...).
    // Firestore can't compare two fields against each other in a query.
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

    func getCatalogItem(code: String) async throws -> HCPCSCatalogItem? {
        let doc = try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .getDocument()
        return try? doc.data(as: HCPCSCatalogItem.self)
    }

    // Note: EXACT match via arrayContains. HCPCSSearchService does smarter
    // substring matching client-side after loading the full catalog.
    func searchCatalog(query: String) async throws -> [HCPCSCatalogItem] {
        let snapshot = try await db.collection("hcpcsCatalog")
            .whereField("commonNames", arrayContains: query.lowercased())
            .whereField("isActive", isEqualTo: true)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HCPCSCatalogItem.self)
        }
    }

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

    func getCatalogItemByGTIN(gtin: String) async throws -> HCPCSCatalogItem? {
        let snapshot = try await db.collection("hcpcsCatalog")
            .whereField("gtins", arrayContains: gtin)
            .limit(to: 1)
            .getDocuments()

        return try? snapshot.documents.first?.data(as: HCPCSCatalogItem.self)
    }

    func getAllCatalogItems() async throws -> [HCPCSCatalogItem] {
        let snapshot = try await db.collection("hcpcsCatalog")
            .order(by: "hcpcsCode")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: HCPCSCatalogItem.self)
        }
    }

    func addGTINToCatalog(code: String, gtin: String) async throws {
        try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .updateData(["gtins": FieldValue.arrayUnion([gtin])])
    }

    func addCommonNameToCatalog(code: String, name: String) async throws {
        try await db.collection("hcpcsCatalog")
            .document(code.uppercased())
            .updateData(["commonNames": FieldValue.arrayUnion([name.lowercased()])])
    }

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
    // ══════════════════════════════════════════════════════

    private func logsCollection(clinicID: String) -> CollectionReference {
        return db.collection("historyLogs")
            .document(clinicID)
            .collection("entries")
    }

    func addLog(_ log: [String: Any], clinicID: String) async throws {
        var logData = log
        logData["clinicID"] = clinicID

        _ = try await logsCollection(clinicID: clinicID)
            .addDocument(data: logData)
        print("Log added to clinic \(clinicID)")
    }

    func getClinicLogs(clinicID: String, limit: Int = 50) async throws -> [HistoryLog] {
        let snapshot = try await logsCollection(clinicID: clinicID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }
    }

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

    func getDeactivatedClinicUsers(clinicID: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("clinicID", isEqualTo: clinicID)
            .whereField("isActive", isEqualTo: false)
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
    // MARK: - INVITATIONS
    // Path: invitations/{email}
    //
    // Note: invitation doc IDs are emails (normalized lowercase), which
    // means one email can only hold one invitation globally. Known
    // limitation — see UserManager for comment.
    // ══════════════════════════════════════════════════════

    func getInvitation(email: String) async throws -> Invitation? {
        let doc = try await db.collection("invitations")
            .document(email)
            .getDocument()
        return try? doc.data(as: Invitation.self)
    }

    func getPendingInvitations(clinicID: String) async throws -> [Invitation] {
        let snapshot = try await db.collection("invitations")
            .whereField("clinicID", isEqualTo: clinicID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: Invitation.self)
        }
    }

    func saveInvitation(_ data: [String: Any], email: String) async throws {
        try await db.collection("invitations")
            .document(email)
            .setData(data)
        print("Invitation saved: \(email)")
    }

    func deleteInvitation(email: String) async throws {
        try await db.collection("invitations")
            .document(email)
            .delete()
        print("Invitation deleted: \(email)")
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
