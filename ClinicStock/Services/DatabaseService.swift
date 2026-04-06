//
//  DatabaseService.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//

import Foundation
import Combine
import FirebaseFirestore

class DatabaseService {
    
    // Singleton - one instance shared across the app
    static let shared = DatabaseService()
    
    // Reference to Firestore
    private let db = Firestore.firestore()
    
    private init() {
        // Enable offline support
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(
            sizeBytes: FirestoreCacheSizeUnlimited as NSNumber
        )
        db.settings = settings
        print("DatabaseService initialized")
    }
    
    // MARK: - INVENTORY
    
    // ── Listen to inventory in real time ──
    // This updates automatically when ANYONE changes data
    func listenToInventory(
        clinicID: String,
        completion: @escaping ([InventoryItem]) -> Void
    ) -> ListenerRegistration {
        
        return db.collection("inventory")
            .whereField("clinicID", isEqualTo: clinicID)
            .order(by: "name")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Inventory listener error: \(error)")
                    completion([])
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No inventory documents")
                    completion([])
                    return
                }
                
                let items = documents.compactMap { doc -> InventoryItem? in
                    try? doc.data(as: InventoryItem.self)
                }
                
                print("Loaded \(items.count) inventory items")
                completion(items)
            }
    }
    
    // ── Get a single item ──
    func getItem(itemID: String) async throws -> InventoryItem? {
        let doc = try await db.collection("inventory")
            .document(itemID)
            .getDocument()
        return try doc.data(as: InventoryItem.self)
    }
    
    // ── Find item by barcode ──
    func findByBarcode(barcode: String, clinicID: String) async throws -> InventoryItem? {
        let snapshot = try await db.collection("inventory")
            .whereField("barcode", isEqualTo: barcode)
            .whereField("clinicID", isEqualTo: clinicID)
            .limit(to: 1)
            .getDocuments()
        
        return try snapshot.documents.first?.data(as: InventoryItem.self)
    }
    
    // ── Check if barcode already exists ──
    func barcodeExists(barcode: String, clinicID: String) async throws -> Bool {
        let snapshot = try await db.collection("inventory")
            .whereField("barcode", isEqualTo: barcode)
            .whereField("clinicID", isEqualTo: clinicID)
            .limit(to: 1)
            .getDocuments()
        
        return !snapshot.documents.isEmpty
    }
    
    // ── Add a new item ──
    func addItem(_ item: [String: Any]) async throws -> String {
        let docRef = try await db.collection("inventory")
            .addDocument(data: item)
        print("Added item: \(docRef.documentID)")
        return docRef.documentID
    }
    
    // ── Update an item ──
    func updateItem(itemID: String, data: [String: Any]) async throws {
        var updateData = data
        updateData["lastUpdated"] = Timestamp(date: Date())
        
        try await db.collection("inventory")
            .document(itemID)
            .updateData(updateData)
        print("Updated item: \(itemID)")
    }
    
    // ── Delete an item ──
    func deleteItem(itemID: String) async throws {
        try await db.collection("inventory")
            .document(itemID)
            .delete()
        print("Deleted item: \(itemID)")
    }
    
    // ═══════════════════════════════════
    // MARK: - HISTORY LOGS
    // ═══════════════════════════════════
    
    // ── Add a log entry ──
    func addLog(_ log: [String: Any]) async throws {
        let _ = try await db.collection("historyLogs")
            .addDocument(data: log)
        print("Log added")
    }
    
    // ── Get logs for a clinic ──
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
    
    // ── Get logs for a specific item ──
    func getItemLogs(itemID: String, limit: Int = 20) async throws -> [HistoryLog] {
        let snapshot = try await db.collection("historyLogs")
            .whereField("itemID", isEqualTo: itemID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap {
            try? $0.data(as: HistoryLog.self)
        }
    }
    
    // ── Listen to recent logs in real time ──
    func listenToRecentLogs(
        clinicID: String,
        limit: Int = 20,
        completion: @escaping ([HistoryLog]) -> Void
    ) -> ListenerRegistration {
        
        return db.collection("historyLogs")
            .whereField("clinicID", isEqualTo: clinicID)
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                let logs = documents.compactMap {
                    try? $0.data(as: HistoryLog.self)
                }
                completion(logs)
            }
    }
    
    // ═══════════════════════════════════
    // MARK: - USERS
    // ═══════════════════════════════════
    
    // ── Get a single user ──
    func getUser(userID: String) async throws -> AppUser? {
        let doc = try await db.collection("users")
            .document(userID)
            .getDocument()
        return try doc.data(as: AppUser.self)
    }
    
    // ── Get all users for a clinic ──
    func getClinicUsers(clinicID: String) async throws -> [AppUser] {
        let snapshot = try await db.collection("users")
            .whereField("clinicID", isEqualTo: clinicID)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        
        return snapshot.documents.compactMap {
            try? $0.data(as: AppUser.self)
        }
    }
    
    // ── Create user profile ──
    func createUserProfile(uid: String, data: [String: Any]) async throws {
        try await db.collection("users")
            .document(uid)
            .setData(data)
        print(" User profile created")
    }
    
    // ── Update user ──
    func updateUser(userID: String, data: [String: Any]) async throws {
        try await db.collection("users")
            .document(userID)
            .updateData(data)
        print("User updated: \(userID)")
    }
    
    // ═══════════════════════════════════
    // MARK: - CLINICS
    // ═══════════════════════════════════
    
    // ── Get all clinics ──
    func getAllClinics() async throws -> [Clinic] {
        let snapshot = try await db.collection("clinics")
            .whereField("isActive", isEqualTo: true)
            .order(by: "name")
            .getDocuments()
        
        return snapshot.documents.compactMap {
            try? $0.data(as: Clinic.self)
        }
    }
    
    // ── Get a single clinic ──
    func getClinic(clinicID: String) async throws -> Clinic? {
        let doc = try await db.collection("clinics")
            .document(clinicID)
            .getDocument()
        return try doc.data(as: Clinic.self)
    }
    
    // ═══════════════════════════════════
    // MARK: - SETTINGS
    // ═══════════════════════════════════
    
    // ── Get categories list ──
    func getCategories() async throws -> [String] {
        let doc = try await db.collection("settings")
            .document("categories")
            .getDocument()
        return doc.data()?["list"] as? [String] ?? []
    }
    
    // ── Get sizes list ──
    func getSizes() async throws -> [String] {
        let doc = try await db.collection("settings")
            .document("sizes")
            .getDocument()
        return doc.data()?["list"] as? [String] ?? []
    }
}
