//
//  AppUser.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//


import Foundation
import FirebaseFirestore

struct AppUser: Codable, Identifiable {
    
    // Fields for user in user/{uid}
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var role: UserRole
    var clinicID: String?
    var phone: String
    var isActive: Bool
    var lastLogin: Date?
    var dateCreated: Date

    // Multi-clinic admin
    var isPlatformAdmin: Bool {
        return role == .admin && clinicID == nil
    }

    // Admin for a single clinic
    var isClinicAdmin: Bool {
        return role == .admin && clinicID != nil
    }

    // Different User Roles
    enum UserRole: String, Codable, CaseIterable {
        case admin
        case manager
        case editor
        case staff

        var displayName: String {
            switch self {
            case .admin:   return "Admin"
            case .manager: return "Manager"
            case .editor:  return "Editor"
            case .staff:   return "Staff"
            }
        }

        var color: String {
            switch self {
            case .admin:   return "red"
            case .manager: return "purple"
            case .editor:  return "blue"
            case .staff:   return "gray"
            }
        }
    }
}
