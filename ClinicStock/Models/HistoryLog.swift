//
//  HistoryLog.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  Audit log entry. Immutable once written — Firestore rules forbid
//  updates and deletes on this collection.
//
//  Field notes:
//  - `updateType` is a denormalization that splits the broad
//    `quantityUpdate` action into "checkout" vs "restock" without
//    requiring a new ActionType case. Lets the History view filter
//    the two separately and lets the void-eligibility logic identify
//    which logs are voidable (checkouts only — you don't "void" a
//    restock, you'd just check stock back out).
//  - `updateType` is optional because older logs predating this field
//    won't have it. New writes set it on every quantityUpdate.
//

import Foundation
import FirebaseFirestore

struct HistoryLog: Codable, Identifiable{
    @DocumentID var id: String?
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

    /// Sub-classification for `quantityUpdate` actions. Values:
    ///   "checkout" — quantity decreased by user action
    ///   "restock" — quantity increased (added stock or new item)
    /// Nil for non-quantityUpdate actions or older logs.
    var updateType: String? = nil

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
