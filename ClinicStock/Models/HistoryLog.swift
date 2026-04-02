//
//  HistoryLog.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
//import FirebaseFirestore

struct HistoryLog: Codable/*, Identifiable*/ {
//    @DocumentID var id: String?
    var itemID: String
    var itemName: String
    var itemBarcode: String
    var userID: String
    var userName: String
    var clinicID: String
    var action: ActionType
    var details: String
    var previousValue: String
    var newValue: String
    var timestamp: Date
    
    enum ActionType: String, Codable, CaseIterable {
        case added
        case deleted
        case quantityUpdate
        case infoUpdate
        case barcodeScan
        case userCreated
        case userUpdated
        case stockAlert
        
        var displayName: String {
            switch self {
            case .added: return "Item Added"
            case .deleted: return "Item Deleted"
            case .quantityUpdate: return "Quantity Changed"
            case .infoUpdate: return "Info Updated"
            case .barcodeScan: return "Barcode Scanned"
            case .userCreated: return "User Created"
            case .userUpdated: return "User Updated"
            case .stockAlert: return "Low Stock Alert"
            }
        }
        
        var icon: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .deleted: return "trash.fill"
            case .quantityUpdate: return "arrow.up.arrow.down.circle.fill"
            case .infoUpdate: return "pencil.circle.fill"
            case .barcodeScan: return "barcode"
            case .userCreated: return "person.badge.plus"
            case .userUpdated: return "person.fill.checkmark"
            case .stockAlert: return "exclamationmark.triangle.fill"
            }
        }
    }
}
