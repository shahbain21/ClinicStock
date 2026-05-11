//
//  DatabaseSeeder.swift
//  ClinicStock
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class DatabaseSeeder: ObservableObject {

    @Published var status: String = "Ready to seed"
    @Published var isSeeding = false
    @Published var isComplete = false
    @Published var lastError: String?

    private let db = Firestore.firestore()
    private let dbService = DatabaseService.shared

    // MARK: - Public

    func reset() {
        isSeeding = false
        isComplete = false
        lastError = nil
        status = "Ready to seed"
    }

    /// Creates a Firebase Auth account, clinic doc, admin profile, default settings,
    /// and sample inventory. Pass `allowIfExisting: true` for multi-clinic test environments.
    func seedDatabase(adminEmail: String, adminPassword: String, allowIfExisting: Bool = false) async {
        isSeeding = true
        isComplete = false
        lastError = nil
        status = "Starting..."

        if !allowIfExisting {
            do {
                let existing = try await db.collection("clinics").limit(to: 1).getDocuments()
                if !existing.documents.isEmpty {
                    fail("Project already has clinics. Pass allowIfExisting: true to seed anyway.", status: "Aborted — project not empty")
                    return
                }
            } catch {
                fail("Pre-seed check failed: \(error.localizedDescription)", status: "Aborted")
                return
            }
        }

        status = "Creating admin auth account..."
        let authResult: AuthDataResult
        do {
            authResult = try await Auth.auth().createUser(withEmail: adminEmail, password: adminPassword)
        } catch {
            fail("Auth account creation failed: \(error.localizedDescription)", status: "Failed")
            return
        }

        let adminUID = authResult.user.uid
        let clinicID: String
        do {
            clinicID = try await commitSeedBatch(adminUID: adminUID)
        } catch {
            try? await authResult.user.delete()
            try? Auth.auth().signOut()
            fail("Batch write failed: \(error.localizedDescription)", status: "Failed — rolled back")
            return
        }

        status = "Adding inventory items..."
        await seedInventory(clinicID: clinicID)

        isSeeding = false
        isComplete = true
        status = "Database setup complete!"
    }

    func seedInventoryOnly(clinicID: String) async {
        isSeeding = true
        isComplete = false
        lastError = nil
        status = "Adding inventory items..."

        await seedInventory(clinicID: clinicID)

        isSeeding = false
        isComplete = true
        status = "Inventory seeded!"
    }

    // MARK: - Private

    private func fail(_ error: String, status: String) {
        lastError = error
        self.status = status
        isSeeding = false
    }

    private func commitSeedBatch(adminUID: String) async throws -> String {
        let clinicRef = db.collection("clinics").document()
        let clinicID  = clinicRef.documentID
        let batch     = db.batch()

        batch.setData([
            "name":        "Specialty Medical Center",
            "address":     "123 Main Street",
            "city":        "Dearborn",
            "state":       "MI",
            "zip":         "48124",
            "phone":       "313-555-0101",
            "email":       "dearborn@clinic.com",
            "managerID":   adminUID,
            "isActive":    true,
            "dateCreated": Timestamp(date: Date())
        ], forDocument: clinicRef)

        batch.setData([
            "email":       "admin@clinicstock.com",
            "displayName": "Admin User",
            "role":        "admin",
            "clinicID":    clinicID,
            "phone":       "313-555-0000",
            "isActive":    true,
            "lastLogin":   Timestamp(date: Date()),
            "dateCreated": Timestamp(date: Date())
        ], forDocument: db.collection("users").document(adminUID))

        batch.setData(["list": [
            "Orthopedic", "Cervical", "Lumbar", "Wound Care",
            "Respiratory", "Diabetic Supplies", "Compression",
            "Mobility Aids", "Electrical Stimulation", "General Medical"
        ]], forDocument: db.collection("settings").document("categories"), merge: true)

        batch.setData(["list": [
            "XS", "S", "M", "L", "XL", "XXL",
            "Universal", "Pediatric", "Custom", "N/A", "RT", "LT"
        ]], forDocument: db.collection("settings").document("sizes"), merge: true)

        try await batch.commit()
        return clinicID
    }

    private func seedInventory(clinicID: String) async {
        let items = sampleInventory(clinicID: clinicID)
        var successCount = 0
        var firstError: String?

        for item in items {
            do {
                _ = try await dbService.addItem(item, clinicID: clinicID)
                successCount += 1
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        status = "Added \(successCount)/\(items.count) inventory items"
        if let err = firstError {
            lastError = "Some items failed. First error: \(err)"
        }
    }

    private func sampleInventory(clinicID: String) -> [[String: Any]] {
        [
            makeItem(name: "LSO Brace",                hcpcs: "L0625", size: "Universal", qty: 51, category: "Lumbar",                clinicID: clinicID),
            makeItem(name: "TENS Unit",                hcpcs: "E0720", size: "N/A",       qty: 71, category: "Electrical Stimulation", clinicID: clinicID),
            makeItem(name: "Knee Brace",               hcpcs: "L1820", size: "S",         qty: 0,  category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Knee Brace",               hcpcs: "L1820", size: "M",         qty: 20, category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Knee Brace",               hcpcs: "L1820", size: "L",         qty: 18, category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Knee Brace",               hcpcs: "L1820", size: "XL",        qty: 23, category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Knee Brace",               hcpcs: "L1820", size: "XXL",       qty: 0,  category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Wrist Brace",              hcpcs: "L3908", size: "Universal", qty: 15, category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "Cervical Collar Coretech", hcpcs: "L0172", size: "Universal", qty: 40, category: "Cervical",              clinicID: clinicID),
            makeItem(name: "Soft Cervical Collar",     hcpcs: "E0120", size: "Universal", qty: 28, category: "Cervical",              clinicID: clinicID),
            makeItem(name: "Cane",                     hcpcs: "E0100", size: "N/A",       qty: 0,  category: "Mobility Aids",         clinicID: clinicID),
            makeItem(name: "Walker",                   hcpcs: "E0130", size: "N/A",       qty: 0,  category: "Mobility Aids",         clinicID: clinicID),
            makeItem(name: "Crutches",                 hcpcs: "E0110", size: "N/A",       qty: 0,  category: "Mobility Aids",         clinicID: clinicID),
            makeItem(name: "Abdominal Binder",         hcpcs: "L0620", size: "Universal", qty: 0,  category: "Lumbar",                clinicID: clinicID),
            makeItem(name: "SI Belt Coretech",         hcpcs: "L0621", size: "Universal", qty: 3,  category: "Lumbar",                clinicID: clinicID, threshold: 5),
            makeItem(name: "ROM Knee Brace",           hcpcs: "L1832", size: "Universal", qty: 0,  category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "OA Knee Brace",            hcpcs: "L1843", size: "RT",        qty: 0,  category: "Orthopedic",            clinicID: clinicID),
            makeItem(name: "OA Knee Brace",            hcpcs: "L1843", size: "LT",        qty: 0,  category: "Orthopedic",            clinicID: clinicID),
        ]
    }

    private func makeItem(
        name: String,
        hcpcs: String,
        size: String,
        qty: Int,
        category: String,
        clinicID: String,
        threshold: Int = 10
    ) -> [String: Any] {
        [
            "name":               name,
            "hcpcsCode":          hcpcs,
            "lotNumber":          "",
            "size":               size,
            "barcode":            "",
            "quantity":           qty,
            "lowStockThreshold":  threshold,
            "clinicID":           clinicID,
            "category":           category,
            "manufacturer":       "",
            "unitCost":           0,
            "lastUpdatedBy":      "system",
            "lastUpdated":        Timestamp(date: Date()),
            "dateAdded":          Timestamp(date: Date()),
            "notes":              ""
        ]
    }
}
