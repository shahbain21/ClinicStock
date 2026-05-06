//
//  Invitation.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/20/26.
//


//
//  Invitation.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Extracted from UserManager.swift for consistency with other model files
//  (AppUser, Clinic, HCPCSCatalogItem, HistoryLog, InventoryItem).
//

import Foundation
import FirebaseFirestore

 struct Invitation: Codable, Identifiable {
    
    // Stored at invitations/{email}
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var role: String
    var clinicID: String
    var invitedBy: String
    var invitedByName: String
    var status: String
    var dateCreated: Date

    var roleEnum: AppUser.UserRole {
        AppUser.UserRole(rawValue: role) ?? .staff
    }

    var isPending: Bool {
        return status == "pending"
    }

    var isAccepted: Bool {
        return status == "accepted"
    }
}
