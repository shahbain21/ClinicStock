//
//  AppUser.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 3/30/26.
//

import Foundation
//import FirebaseFirestore

struct AppUser: Codable/*, Identifiable*/ {
//    @DocumentID var id: String?
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
        case clinicManager
        case editor
        case viewer
        
        var displayName: String {
            switch self {
            case .admin: return "Admin"
            case .clinicManager: return "Clinic Manager"
            case .editor: return "Editor"
            case .viewer: return "Viewer"
            }
        }
        
        var color: String {
            switch self {
            case .admin: return "red"
            case .clinicManager: return "purple"
            case .editor: return "blue"
            case .viewer: return "gray"
            }
        }
    }
}
