//
//  InventoryItem.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
import FirebaseFirestore

struct InventoryItem: Codable, Identifiable, Hashable{
    
    // Stored at path inventory/{clinicID}/items/{itemID} 
    @DocumentID var id: String?
    var name: String
    var hcpcsCode: String
    var lotNumber: String
    var size: String
    var barcode: String
    var quantity: Int
    var lowStockThreshold: Int
    var clinicID: String
    var category: String
    var manufacturer: String
    var unitCost: Double?
    var lastUpdatedBy: String
    var lastUpdated: Date
    var dateAdded: Date
    var notes: String
    
    var isLowStock: Bool {
        return quantity <= lowStockThreshold && quantity > 0
    }
    
    var isOutOfStock: Bool {
        return quantity <= 0
    }
    
    var totalValue: Double {
        return Double(quantity) * (unitCost ?? 0)
    }
}
