// DatabaseSeeder.swift

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine 

class DatabaseSeeder: ObservableObject {
    
    @Published var status: String = "Ready to seed"
    @Published var isSeeding: Bool = false
    @Published var isComplete: Bool = false
    
    private let db = Firestore.firestore()
    
    // ══════════════════════════════════════════
    // Run this ONCE to set up your database
    // ══════════════════════════════════════════
    
    func seedDatabase() async {
        await MainActor.run {
            isSeeding = true
            status = "Starting..."
        }
        
        // Step 1: Create the clinic
        await updateStatus("Creating clinic...")
        let clinicID = await createClinic()
        
        guard let clinicID = clinicID else {
            await updateStatus(" Failed to create clinic")
            return
        }
        
        // Step 2: Create the admin account
        await updateStatus("Creating admin account...")
        await createAdminAccount(clinicID: clinicID)
        
        // Step 3: Create app settings
        await updateStatus("Creating settings...")
        await createSettings()
        
        // Step 4: Add inventory from checklist
        await updateStatus("Adding inventory items...")
//        await createInventory(clinicID: clinicID)
        
        // Done!
        await MainActor.run {
            isSeeding = false
            isComplete = true
            status = "Database setup complete!"
        }
    }
    
    // ── Create Clinic ──
    private func createClinic() async -> String? {
        do {
            let clinicRef = db.collection("clinics").document()
            
            try await clinicRef.setData([
                "name": "Specialty Medical Center",
                "address": "123 Main Street",
                "city": "Dearborn",
                "state": "MI",
                "zip": "48124",
                "phone": "313-555-0101",
                "email": "dearborn@clinic.com",
                "managerID": "",
                "isActive": true,
                "dateCreated": Timestamp(date: Date())
            ])
            
            print("Clinic created: \(clinicRef.documentID)")
            return clinicRef.documentID
            
        } catch {
            print("Error creating clinic: \(error)")
            return nil
        }
    }
    
    // ── Create Admin Account ──
    private func createAdminAccount(clinicID: String) async {
        do {
            // Create Firebase Auth account
            let result = try await Auth.auth().createUser(
                withEmail: "admin@clinicstock.com",
                password: "Test1234!"
            )
            
            let uid = result.user.uid
            
            // Create user profile in Firestore
            try await db.collection("users").document(uid).setData([
                "email": "admin@clinicstock.com",
                "displayName": "Admin User",
                "role": "admin",
                "clinicID": clinicID,
                "phone": "313-555-0000",
                "isActive": true,
                "lastLogin": Timestamp(date: Date()),
                "dateCreated": Timestamp(date: Date())
            ])
            
            // Sign out so we can test logging in
            try Auth.auth().signOut()
            
            print("Admin account created")
            print("Email: admin@clinicstock.com")
            print("Password: Test1234!")
            
        } catch {
            print("Error creating admin: \(error)")
        }
    }
    
    // ── Create Settings ──
    private func createSettings() async {
        do {
            try await db.collection("settings").document("categories").setData([
                "list": [
                    "Orthopedic",
                    "Cervical",
                    "Lumbar",
                    "Wound Care",
                    "Respiratory",
                    "Diabetic Supplies",
                    "Compression",
                    "Mobility Aids",
                    "Electrical Stimulation",
                    "General Medical"
                ]
            ])
            
            try await db.collection("settings").document("sizes").setData([
                "list": [
                    "XS", "S", "M", "L", "XL", "XXL",
                    "Universal", "Pediatric", "Custom",
                    "N/A", "RT", "LT"
                ]
            ])
            
            print("Settings created")
            
        } catch {
            print("Error creating settings: \(error)")
        }
    }
    
    // ── Create Inventory (from your Dearborn checklist) ──
//    private func createInventory(clinicID: String) async {
//        
//        let items: [[String: Any]] = [
//            makeItem(name: "LSO Brace", hcpcs: "L0625", size: "Universal",
//                    qty: 51, category: "Lumbar", clinicID: clinicID),
//            
//            makeItem(name: "TENS Unit", hcpcs: "E0720", size: "N/A",
//                    qty: 71, category: "Electrical Stimulation", clinicID: clinicID),
//            
//            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "S",
//                    qty: 0, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "M",
//                    qty: 20, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "L",
//                    qty: 18, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "XL",
//                    qty: 23, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Knee Brace", hcpcs: "L1820", size: "XXL",
//                    qty: 0, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Wrist Brace", hcpcs: "L3908", size: "Universal",
//                    qty: 15, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "Cervical Collar Coretech", hcpcs: "L0172", size: "Universal",
//                    qty: 40, category: "Cervical", clinicID: clinicID),
//            
//            makeItem(name: "Soft Cervical Collar", hcpcs: "L0120", size: "Universal",
//                    qty: 28, category: "Cervical", clinicID: clinicID),
//            
//            makeItem(name: "Cane", hcpcs: "E0100", size: "N/A",
//                    qty: 0, category: "Mobility Aids", clinicID: clinicID),
//            
//            makeItem(name: "Walker", hcpcs: "E0130", size: "N/A",
//                    qty: 0, category: "Mobility Aids", clinicID: clinicID),
//            
//            makeItem(name: "Crutches", hcpcs: "E0110", size: "N/A",
//                    qty: 0, category: "Mobility Aids", clinicID: clinicID),
//            
//            makeItem(name: "Abdominal Binder", hcpcs: "L0620", size: "Universal",
//                    qty: 0, category: "Lumbar", clinicID: clinicID),
//            
//            makeItem(name: "SI Belt Coretech", hcpcs: "L0621", size: "Universal",
//                    qty: 3, threshold: 5, category: "Lumbar", clinicID: clinicID),
//            
//            makeItem(name: "ROM Knee Brace", hcpcs: "L1832", size: "Universal",
//                    qty: 0, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "OA Knee Brace", hcpcs: "L1843", size: "RT",
//                    qty: 0, category: "Orthopedic", clinicID: clinicID),
//            
//            makeItem(name: "OA Knee Brace", hcpcs: "L1843", size: "LT",
//                    qty: 0, category: "Orthopedic", clinicID: clinicID),
//        ]
//        
//        for item in items {
//            do {
//                let _ = try await db.collection("inventory").addDocument(data: item)
//                print("Added: \(item["name"] ?? "") (\(item["size"] ?? ""))")
//            } catch {
//                print("Error adding item: \(error)")
//            }
//        }
//        
//        print(" Added \(items.count) inventory items")
//    }
    
    // Helper: build an item dictionary
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
            "originalQuantity": qty,
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
    
    // Helper: update status on main thread
    private func updateStatus(_ message: String) async {
        await MainActor.run {
            status = message
        }
        print(message)
    }
}
