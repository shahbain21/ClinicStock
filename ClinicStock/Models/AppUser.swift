//
//  AppUser.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//
//  CHANGED: clinicID is now optional.
//    - nil   → platform admin with multi-clinic access (you, the owner)
//    - set   → user belongs to one specific clinic (everyone else)
//
//  The role field still governs permissions within the clinic the user
//  is currently viewing. A clinicID-less admin sees everything.
//

import Foundation
import FirebaseFirestore

struct AppUser: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var role: UserRole
    var clinicID: String?
    var phone: String
    var isActive: Bool
    var lastLogin: Date?
    var dateCreated: Date

    /// True when this user is a platform-level admin (owns multiple
    /// clinics). UI and services use this to branch on special
    /// admin-only flows like the clinic switcher.
    var isPlatformAdmin: Bool {
        return role == .admin && clinicID == nil
    }

    /// True when this user is admin of a single clinic — the pre-
    /// multi-clinic admin model, still valid for clinics that signed
    /// up independently.
    var isClinicAdmin: Bool {
        return role == .admin && clinicID != nil
    }

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
