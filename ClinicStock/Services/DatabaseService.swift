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
    // MARK: - AGGREGATE INVENTORY (cross-clinic)
    //
    // Used by platform admin's "All Clinics" view. Fetches inventory
    // from every active clinic in parallel. Each item still carries
    // its own clinicID (preserved from the source document), so the
    // caller can group by clinic for display.
    //
    // Not a listener — listeners are per-collection in Firestore, and
    // we'd need one per clinic to keep up. For aggregate view that
    // overhead isn't worth it. Reload on pull-to-refresh instead.
    // ══════════════════════════════════════════════════════

    func getAllInventoryAcrossClinics() async throws -> [InventoryItem] {
        let clinics = try await getAllClinics()

        // Fetch every clinic's items concurrently. TaskGroup keeps the
        // total wall-time roughly equal to the slowest single fetch
        // rather than the sum of all fetches.
        return try await withThrowingTaskGroup(of: [InventoryItem].self) { group in
            for clinic in clinics {
                guard let clinicID = clinic.id else { continue }
                group.addTask {
                    let snapshot = try await self.itemsCollection(clinicID: clinicID)
                        .getDocuments()
                    return snapshot.documents.compactMap {
                        try? $0.data(as: InventoryItem.self)
                    }
                }
            }

            var combined: [InventoryItem] = []
            for try await items in group {
                combined.append(contentsOf: items)
            }
            return combined
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - AGGREGATE HISTORY (cross-clinic)
    //
    // Used by platform admin's "All Clinics" history view. Same
    // pagination semantics as getClinicLogsPage but no clinicID filter.
    //
    // NOTE: The composite index for (action + timestamp DESC) without
    // clinicID will need to be created the first time you filter by
    // action in aggregate mode. Firestore prints the URL on the first
    // failed query.
    // ══════════════════════════════════════════════════════

    func getAllLogsPage(
        pageSize: Int = 50,
        startAfter: DocumentSnapshot? = nil,
        actions: [String]? = nil,
        updateType: String? = nil
    ) async throws -> LogsPage {
        var query: Query = db.collection("historyLogs")

        if let actions = actions, !actions.isEmpty {
            query = query.whereField("action", in: Array(actions.prefix(10)))
        }

        if let updateType = updateType {
            query = query.whereField("updateType", isEqualTo: updateType)
        }

        query = query
            .order(by: "timestamp", descending: true)
            .limit(to: pageSize)

        if let cursor = startAfter {
            query = query.start(afterDocument: cursor)
        }

        let snapshot = try await query.getDocuments()

        let logs = snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }

        let lastDoc: DocumentSnapshot?
        if snapshot.documents.count < pageSize {
            lastDoc = nil
        } else {
            lastDoc = snapshot.documents.last
        }

        return LogsPage(logs: logs, lastDocument: lastDoc)
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

    // ── Paginated clinic logs ──
    //
    // Returns a page of logs plus the last document in the page, which
    // the caller passes back in on the next call to get the next page.
    // The non-paginated overload below is kept for callers that just
    // need the most recent N logs (e.g. Dashboard recent activity).
    struct LogsPage {
        let logs: [HistoryLog]
        let lastDocument: DocumentSnapshot?

        var hasMore: Bool {
            // If we got as many docs as requested, there's probably more.
            // Cheaper than a separate count query. Caller can stop paging
            // when a Load More returns fewer than `pageSize`.
            return lastDocument != nil
        }
    }

    func getClinicLogsPage(
        clinicID: String,
        pageSize: Int = 50,
        startAfter: DocumentSnapshot? = nil,
        actions: [String]? = nil,
        updateType: String? = nil
    ) async throws -> LogsPage {
        var query: Query = db.collection("historyLogs")
            .whereField("clinicID", isEqualTo: clinicID)

        // Optional filter by action types (for the filter pills).
        // Firestore 'in' supports up to 10 values.
        if let actions = actions, !actions.isEmpty {
            query = query.whereField("action", in: Array(actions.prefix(10)))
        }

        // Optional finer-grained filter for the quantityUpdate split.
        // Only logs written after we started denormalizing this field
        // will match — older logs lack it, so they'll be invisible when
        // the caller filters on updateType. Acceptable: Checkouts /
        // Restocks pills are forward-looking.
        if let updateType = updateType {
            query = query.whereField("updateType", isEqualTo: updateType)
        }

        query = query
            .order(by: "timestamp", descending: true)
            .limit(to: pageSize)

        if let cursor = startAfter {
            query = query.start(afterDocument: cursor)
        }

        let snapshot = try await query.getDocuments()

        let logs = snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }

        // If we got fewer results than the page size, there's no more
        // data — signal that by returning nil for the cursor.
        let lastDoc: DocumentSnapshot?
        if snapshot.documents.count < pageSize {
            lastDoc = nil
        } else {
            lastDoc = snapshot.documents.last
        }

        return LogsPage(logs: logs, lastDocument: lastDoc)
    }

    // Legacy overload — returns a flat array, used by places that only
    // want the most recent N (Dashboard, ItemDetail).
    func getClinicLogs(clinicID: String, limit: Int = 50) async throws -> [HistoryLog] {
        let page = try await getClinicLogsPage(
            clinicID: clinicID,
            pageSize: limit
        )
        return page.logs
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
    // Document ID is the lowercased, trimmed email — used directly
    // (Firestore document IDs do allow '.', so no encoding needed).
    //
    // Keyed by email because:
    //  1. A single pending invitation per email prevents accidental
    //     duplicates when re-inviting.
    //  2. checkAndAcceptInvitation on sign-in needs to look up by
    //     email (the only thing we know about a user at auth time).
    // ══════════════════════════════════════════════════════

    /// Normalize an email into the form used as an invitation doc ID.
    /// All read/write paths must use this so they all hit the same
    /// document.
    private func invitationDocID(for email: String) -> String {
        return email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
        // No filtering on the query side — fetches ALL clinics, then
        // filters and sorts in memory. This avoids needing a Firestore
        // composite index for (isActive==true + order by name), which
        // is overkill for the small number of clinics any one platform
        // admin will have.
        //
        // If clinic count grows past hundreds, switch back to a query-
        // side filter and create the composite index. Until then this
        // is faster end-to-end (one round trip, no index build).
        let snapshot = try await db.collection("clinics")
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: Clinic.self) }
            .filter { $0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Includes archived (isActive == false) clinics. Only platform
    /// admin should call this — the Manage Clinics screen needs to
    /// see archived clinics so admin can restore them. Regular flows
    /// (picker, switching) use the filtered version above.
    func getAllClinicsIncludingArchived() async throws -> [Clinic] {
        let snapshot = try await db.collection("clinics")
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: Clinic.self) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Returns clinics that have been archived (soft-deleted). Used by
    /// the "Archived Clinics" admin screen to list candidates for
    /// restoration.
    func getArchivedClinics() async throws -> [Clinic] {
        let snapshot = try await db.collection("clinics")
            .getDocuments()

        return snapshot.documents
            .compactMap { try? $0.data(as: Clinic.self) }
            .filter { !$0.isActive }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

    /// Global default low-stock threshold. Used as the initial value
    /// when adding a new inventory item — existing items keep their
    /// own per-item threshold and aren't affected when this changes.
    ///
    /// Returns 10 if no value has been saved yet (sensible default
    /// matching the old hardcoded value in AddItemView).
    func getLowStockDefault() async throws -> Int {
        let doc = try await db.collection("settings")
            .document("lowStockDefault")
            .getDocument()
        return doc.data()?["value"] as? Int ?? 10
    }

    func setLowStockDefault(_ value: Int) async throws {
        try await db.collection("settings")
            .document("lowStockDefault")
            .setData(["value": value], merge: true)
        print("Low stock default updated: \(value)")
    }

    /// Bulk-update every inventory item across every active clinic to
    /// the given threshold. Used when admin chooses "Apply to all items"
    /// after changing the global default — the heavy-hammer version
    /// that overwrites any per-item customization.
    ///
    /// Returns a tuple of (succeeded, failed) item counts so the UI
    /// can report partial failures. Failures are usually permission
    /// denials on a specific item, network blips, etc. — they don't
    /// abort the whole operation, we just keep going.
    ///
    /// This uses Firestore batched writes (max 500 ops per batch) so
    /// large clinics stay within transactional limits.
    func applyLowStockThresholdToAllItems(_ threshold: Int) async throws -> (succeeded: Int, failed: Int) {
        let clinics = try await getAllClinics()
        var succeeded = 0
        var failed = 0

        for clinic in clinics {
            guard let clinicID = clinic.id else { continue }

            do {
                let snapshot = try await itemsCollection(clinicID: clinicID)
                    .getDocuments()

                // Firestore batches max 500 writes. Chunk if needed.
                let chunks = stride(from: 0, to: snapshot.documents.count, by: 500).map {
                    Array(snapshot.documents[$0..<min($0 + 500, snapshot.documents.count)])
                }

                for chunk in chunks {
                    let batch = db.batch()
                    for doc in chunk {
                        batch.updateData([
                            "lowStockThreshold": threshold,
                            "lastUpdated": Timestamp(date: Date())
                        ], forDocument: doc.reference)
                    }

                    do {
                        try await batch.commit()
                        succeeded += chunk.count
                    } catch {
                        print("Batch commit failed for clinic \(clinicID): \(error)")
                        failed += chunk.count
                    }
                }

                print("Updated \(snapshot.documents.count) items in clinic \(clinicID)")

            } catch {
                print("Couldn't read items for clinic \(clinicID): \(error)")
                // We don't know how many would have been updated, so
                // can't increment failed by a known count. Move on.
            }
        }

        return (succeeded: succeeded, failed: failed)
    }
}
