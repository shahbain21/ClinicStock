//
//  AppUser.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
import FirebaseFirestore

struct AppUser: Codable, Identifiable{
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var role: UserRole
    var clinicID: String
    var phone: String
    var isActive: Bool
    var lastLogin: Date?
    var dateCreated: Date
    
    enum UserRole: String, Codable, CaseIterable {
        case admin
        case manager
        case editor
        case staff
        
        var displayName: String {
            switch self {
            case .admin: return "Admin"
            case .manager: return "Manager"
            case .editor: return "Editor"
            case .staff: return "Staff"
            }
        }
        
        var color: String {
            switch self {
            case .admin: return "red"
            case .manager: return "purple"
            case .editor: return "blue"
            case .staff: return "gray"
            }
        }
    }
}
