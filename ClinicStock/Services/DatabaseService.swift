//
//  DatabaseService.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  Refactored to use subcollections:
//  inventory/{clinicID}/items/{itemID}
//
//  clinicID is kept on each document AND in the path.
//  Redundant by design — easier debugging, no future bugs.
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

    // ── Find item by barcode (tries multiple format variants) ──
    //
    // The caller passes a list of candidate strings — typically the raw
    // scanned value plus a couple of normalized forms (14-digit GTIN,
    // 13-digit stripped). Firestore's `in` operator matches any of them
    // in a single query, which handles older items that were stored
    // under a different format than what the scanner returns today.
    //
    // The legacy single-barcode call site is preserved as a convenience
    // wrapper that forwards to this array version.
    func findByBarcode(candidates: [String], clinicID: String) async throws -> InventoryItem? {
        let uniqueCandidates = Array(Set(candidates.filter { !$0.isEmpty })).prefix(10)
        guard !uniqueCandidates.isEmpty else { return nil }

        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", in: Array(uniqueCandidates))
            .limit(to: 1)
            .getDocuments()

        return try? snapshot.documents.first?.data(as: InventoryItem.self)
    }

    // Convenience overload for single-barcode callers.
    func findByBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        return try await findByBarcode(candidates: [barcode], clinicID: clinicID)
    }

    // ── Check if barcode already exists (tries multiple format variants) ──
    func barcodeExists(candidates: [String], clinicID: String) async throws -> Bool {
        let uniqueCandidates = Array(Set(candidates.filter { !$0.isEmpty })).prefix(10)
        guard !uniqueCandidates.isEmpty else { return false }

        let snapshot = try await itemsCollection(clinicID: clinicID)
            .whereField("barcode", in: Array(uniqueCandidates))
            .limit(to: 1)
            .getDocuments()

        return !snapshot.documents.isEmpty
    }

    func barcodeExists(barcode: String, clinicID: String) async throws -> Bool {
        return try await barcodeExists(candidates: [barcode], clinicID: clinicID)
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

    // ── Search catalog by common name ──
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
    // ══════════════════════════════════════════════════════

    // ── Write a new history log ──
    //
    // Accepts clinicID as a separate parameter so callers don't have to
    // remember to bake it into the log dict. We inject it before write
    // so every log document has a clinicID field (required by our
    // listenToRecentLogs / getClinicLogs queries, which filter on it).
    func addLog(_ log: [String: Any], clinicID: String) async throws {
        var enrichedLog = log
        enrichedLog["clinicID"] = clinicID
        if enrichedLog["timestamp"] == nil {
            enrichedLog["timestamp"] = Timestamp(date: Date())
        }

        let _ = try await db.collection("historyLogs")
            .addDocument(data: enrichedLog)
        print("Log added for clinic \(clinicID)")
    }

    // Convenience overload for logs that already have clinicID baked in.
    // Prefer the explicit form above for new call sites.
    func addLog(_ log: [String: Any]) async throws {
        guard let clinicID = log["clinicID"] as? String else {
            print("addLog called without clinicID — log dropped")
            return
        }
        try await addLog(log, clinicID: clinicID)
    }

    func getClinicLogs(clinicID: String, limit: Int = 50) async throws -> [HistoryLog] {
        let snapshot = try await db.collection("historyLogs")
            .whereField("clinicID", isEqualTo: clinicID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }
    }

    func getItemLogs(
        itemID: String,
        clinicID: String,
        limit: Int = 20
    ) async throws -> [HistoryLog] {
        let snapshot = try await db.collection("historyLogs")
            .whereField("itemID", isEqualTo: itemID)
            .whereField("clinicID", isEqualTo: clinicID)
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

        return db.collection("historyLogs")
            .whereField("clinicID", isEqualTo: clinicID)
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
    // Path: invitations/{normalized-email}
    //
    // Keyed by email (lowercased, trimmed) because:
    //  1. A single pending invitation per email prevents accidental
    //     duplicates when re-inviting.
    //  2. checkAndAcceptInvitation on sign-in needs to look up by email
    //     (the only thing we know about a user at auth time).
    //
    // Firestore document IDs can't contain '.', '#', '$', '[', or ']'
    // — but email addresses regularly contain '.'. We percent-encode
    // the dot when deriving the document ID. Reads/writes go through
    // a helper so callers use plain emails.
    // ══════════════════════════════════════════════════════

    private func invitationDocID(for email: String) -> String {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // Only the dot is problematic in practice for valid emails.
        // Use %2E so the encoding is stable and round-trippable.
        return normalized.replacingOccurrences(of: ".", with: "%2E")
    }

    func getInvitation(email: String) async throws -> Invitation? {
        let docID = invitationDocID(for: email)
        let doc = try await db.collection("invitations")
            .document(docID)
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
        var enriched = data
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Always set the email field in the stored doc to the normalized
        // form, regardless of what the caller put in the dict. This keeps
        // queries that filter by email reliable.
        enriched["email"] = normalized
        if enriched["dateCreated"] == nil {
            enriched["dateCreated"] = Timestamp(date: Date())
        }

        let docID = invitationDocID(for: normalized)
        try await db.collection("invitations")
            .document(docID)
            .setData(enriched, merge: true)
        print("Invitation saved: \(normalized)")
    }

    // Convenience overload for callers that have email inside the dict.
    // Prefer the explicit form above.
    func saveInvitation(_ data: [String: Any]) async throws {
        guard let email = data["email"] as? String else {
            print("saveInvitation called without email — dropped")
            return
        }
        try await saveInvitation(data, email: email)
    }

    func deleteInvitation(email: String) async throws {
        let docID = invitationDocID(for: email)
        try await db.collection("invitations")
            .document(docID)
            .delete()
        print("Invitation deleted: \(email)")
    }

    func updateInvitation(email: String, data: [String: Any]) async throws {
        let docID = invitationDocID(for: email)
        try await db.collection("invitations")
            .document(docID)
            .updateData(data)
        print("Invitation updated: \(email)")
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

    func getClinic(clinicID: String) async throws -> Clinic? {
        let doc = try await db.collection("clinics")
            .document(clinicID)
            .getDocument()
        return try? doc.data(as: Clinic.self)
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
