//
//  InventoryItem.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
//import FirebaseFirestore

struct InventoryItem: Codable/*, Identifiable*/ {
//    @DocumentID var id: String?
    var name: String
    var hcpcsCode: String
    var lotNumber: String
    var size: String
    var barcode: String
    var quantity: Int
    var originalQuantity: Int
    var lowStockThreshold: Int
    var clinicID: String
    var category: String
    var manufacturer: String
    var unitCost: Double?
    var lastUpdatedBy: String
    var lastUpdated: Date
    var dateAdded: Date
    var notes: String
    
    var quantityUsed: Int {
        return originalQuantity - quantity
    }
    
    var isLowStock: Bool {
        return quantity <= lowStockThreshold
    }
    
    var isOutOfStock: Bool {
        return quantity <= 0
    }
    
    var percentRemaining: Double {
        guard originalQuantity > 0 else { return 0 }
        return (Double(quantity) / Double(originalQuantity)) * 100
    }
    
    var totalValue: Double {
        return Double(quantity) * (unitCost ?? 0)
    }
}



struct HCPCSCode: Codable, Identifiable, Hashable {
    var id: String { code }
    var code: String
    var description: String
}
