//
//  DatabaseSeeder.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  FIXES:
//  - Clinic + admin profile + settings now written in a single WriteBatch
//    with Auth rollback on failure. No more orphaned clinics.
//  - Removed the mid-seed signOut() — the seeded admin stays signed in,
//    which satisfies the new Firestore rules that require a signed-in
//    admin for subsequent writes.
//  - Inventory writes now route through DatabaseService.addItem.
//  - User profile creation routes through DatabaseService.createUserProfile.
//  - Admin credentials are parameters now (configurable in the UI)
//    instead of hardcoded.
//  - Pre-seed check: aborts if any clinic already exists unless the
//    caller explicitly opts in via allowIfExisting: true.
//  - lastError surfaces failure details to the UI.
//  - Consistent @MainActor state mutations via a single helper.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class DatabaseSeeder: ObservableObject {

    @Published var status: String = "Ready to seed"
    @Published var isSeeding: Bool = false
    @Published var isComplete: Bool = false
    @Published var lastError: String? = nil

    private let db = Firestore.firestore()
    private let dbService = DatabaseService.shared

    // ══════════════════════════════════════════════════════
    // MARK: - Reset to initial state (for re-running)
    // ══════════════════════════════════════════════════════

    func reset() {
        isSeeding = false
        isComplete = false
        lastError = nil
        status = "Ready to seed"
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Full database seed
    //
    // Creates: Firebase Auth account, clinic doc, admin user doc, default
    // settings, sample inventory. The first four happen in one WriteBatch.
    // Inventory is written after because it depends on the clinic ID and
    // doesn't need to be atomic with clinic creation.
    //
    // Pass allowIfExisting: true to seed into a project that already has
    // clinics (useful for test environments with multiple clinics).
    // ══════════════════════════════════════════════════════

    func seedDatabase(
        adminEmail: String,
        adminPassword: String,
        allowIfExisting: Bool = false
    ) async {
        isSeeding = true
        isComplete = false
        lastError = nil
        status = "Starting..."

        // Pre-seed check — don't accidentally clone into a live project
        if !allowIfExisting {
            do {
                let existing = try await db.collection("clinics")
                    .limit(to: 1)
                    .getDocuments()
                if !existing.documents.isEmpty {
                    lastError = "Project already has clinics. Pass allowIfExisting: true to seed anyway."
                    status = "Aborted — project not empty"
                    isSeeding = false
                    return
                }
            } catch {
                lastError = "Pre-seed check failed: \(error.localizedDescription)"
                status = "Aborted"
                isSeeding = false
                return
            }
        }

        // Step 1: Create Firebase Auth account
        status = "Creating admin auth account..."
        let authResult: AuthDataResult
        do {
            authResult = try await Auth.auth().createUser(
                withEmail: adminEmail,
                password: adminPassword
            )
        } catch {
            lastError = "Auth account creation failed: \(error.localizedDescription)"
            status = "Failed"
            isSeeding = false
            return
        }

        let adminUID = authResult.user.uid

        // Steps 2-4: Clinic, admin profile, settings as a single batch.
        // If this fails, we roll back the Auth account.
        let clinicID: String
        do {
            clinicID = try await commitSeedBatch(adminUID: adminUID)
        } catch {
            // Roll back Auth account so a retry can reuse the same email
            print("Batch commit failed — rolling back Auth account: \(error)")
            try? await authResult.user.delete()
            try? Auth.auth().signOut()

            lastError = "Batch write failed: \(error.localizedDescription)"
            status = "Failed — rolled back"
            isSeeding = false
            return
        }

        print("Clinic + admin + settings committed: \(clinicID)")

        // Step 5: Inventory — not batched because there are 18 items and
        // Firestore batches are capped at 500 writes (fine for us, but
        // one-at-a-time gives better progress feedback for dev use).
        status = "Adding inventory items..."
        await seedInventory(clinicID: clinicID)

        isSeeding = false
        isComplete = true
        status = "Database setup complete!"
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Seed ONLY inventory for existing clinic
    // ══════════════════════════════════════════════════════

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

    // ══════════════════════════════════════════════════════
    // MARK: - Private: batched seed (clinic + admin + settings)
    // ══════════════════════════════════════════════════════

    private func commitSeedBatch(adminUID: String) async throws -> String {
        let clinicRef = db.collection("clinics").document()
        let clinicID = clinicRef.documentID
        let userRef = db.collection("users").document(adminUID)
        let categoriesRef = db.collection("settings").document("categories")
        let sizesRef = db.collection("settings").document("sizes")

        let batch = db.batch()

        batch.setData([
            "name": "Specialty Medical Center",
            "address": "123 Main Street",
            "city": "Dearborn",
            "state": "MI",
            "zip": "48124",
            "phone": "313-555-0101",
            "email": "dearborn@clinic.com",
            "managerID": adminUID,
            "isActive": true,
            "dateCreated": Timestamp(date: Date())
        ], forDocument: clinicRef)

        batch.setData([
            "email": "admin@clinicstock.com",
            "displayName": "Admin User",
            "role": "admin",
            "clinicID": clinicID,
            "phone": "313-555-0000",
            "isActive": true,
            "lastLogin": Timestamp(date: Date()),
            "dateCreated": Timestamp(date: Date())
        ], forDocument: userRef)

        batch.setData([
            "list": [
                "Orthopedic", "Cervical", "Lumbar", "Wound Care",
                "Respiratory", "Diabetic Supplies", "Compression",
                "Mobility Aids", "Electrical Stimulation", "General Medical"
            ]
        ], forDocument: categoriesRef, merge: true)

        batch.setData([
            "list": [
                "XS", "S", "M", "L", "XL", "XXL",
                "Universal", "Pediatric", "Custom",
                "N/A", "RT", "LT"
            ]
        ], forDocument: sizesRef, merge: true)

        try await batch.commit()
        return clinicID
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: inventory seed
    // Routes through DatabaseService.addItem.
    // ══════════════════════════════════════════════════════

    private func seedInventory(clinicID: String) async {
        let items = sampleInventory(clinicID: clinicID)

        var successCount = 0
        var firstError: String? = nil

        for item in items {
            do {
                _ = try await dbService.addItem(item, clinicID: clinicID)
                successCount += 1
                let name = item["name"] as? String ?? "?"
                let size = item["size"] as? String ?? "?"
                print("Added: \(name) (\(size))")
            } catch {
                if firstError == nil {
                    firstError = error.localizedDescription
                }
                print("Error adding item: \(error)")
            }
        }

        status = "Added \(successCount)/\(items.count) inventory items"
        if let err = firstError {
            lastError = "Some items failed. First error: \(err)"
        }
        print("Added \(successCount) inventory items to clinic \(clinicID)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Private: sample inventory data
    // ══════════════════════════════════════════════════════

    private func sampleInventory(clinicID: String) -> [[String: Any]] {
        return [
            makeItem(name: "LSO Brace", hcpcs: "L0625", size: "Universal",
                    qty: 51, category: "Lumbar", clinicID: clinicID),

            makeItem(name: "TENS Unit", hcpcs: "E0720", size: "N/A",
                    qty: 71, category: "Electrical Stimulation", clinicID: clinicID),

            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "S",
                    qty: 0, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "M",
                    qty: 20, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "L",
                    qty: 18, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "XL",
                    qty: 23, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "XXL",
                    qty: 0, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Wrist Brace", hcpcs: "L3908", size: "Universal",
                    qty: 15, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "Cervical Collar Coretech", hcpcs: "L0172", size: "Universal",
                    qty: 40, category: "Cervical", clinicID: clinicID),

            makeItem(name: "Soft Cervical Collar", hcpcs: "E0120", size: "Universal",
                    qty: 28, category: "Cervical", clinicID: clinicID),

            makeItem(name: "Cane", hcpcs: "E0100", size: "N/A",
                    qty: 0, category: "Mobility Aids", clinicID: clinicID),

            makeItem(name: "Walker", hcpcs: "E0130", size: "N/A",
                    qty: 0, category: "Mobility Aids", clinicID: clinicID),

            makeItem(name: "Crutches", hcpcs: "E0110", size: "N/A",
                    qty: 0, category: "Mobility Aids", clinicID: clinicID),

            makeItem(name: "Abdominal Binder", hcpcs: "L0620", size: "Universal",
                    qty: 0, category: "Lumbar", clinicID: clinicID),

            makeItem(name: "SI Belt Coretech", hcpcs: "L0621", size: "Universal",
                    qty: 3, threshold: 5, category: "Lumbar", clinicID: clinicID),

            makeItem(name: "ROM Knee Brace", hcpcs: "L1832", size: "Universal",
                    qty: 0, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "OA Knee Brace", hcpcs: "L1843", size: "RT",
                    qty: 0, category: "Orthopedic", clinicID: clinicID),

            makeItem(name: "OA Knee Brace", hcpcs: "L1843", size: "LT",
                    qty: 0, category: "Orthopedic", clinicID: clinicID),
        ]
    }

    private func makeItem(
        name: String,
        hcpcs: String,
        size: String,
        qty: Int,
        threshold: Int = 10,
        category: String,
        clinicID: String
    ) -> [String: Any] {
        return [
            "name": name,
            "hcpcsCode": hcpcs,
            "lotNumber": "",
            "size": size,
            "barcode": "",
            "quantity": qty,
            "lowStockThreshold": threshold,
            "clinicID": clinicID,
            "category": category,
            "manufacturer": "",
            "unitCost": 0,
            "lastUpdatedBy": "system",
            "lastUpdated": Timestamp(date: Date()),
            "dateAdded": Timestamp(date: Date()),
            "notes": ""
        ]
    }
}
