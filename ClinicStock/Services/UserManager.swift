//
//  UserManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  REWRITTEN: Invitation-based system
//  - Admin creates invitations, not Auth accounts
//  - No auto-sign-in problem
//  - Works with Google/Apple/Email sign-in
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

class UserManager: ObservableObject {

    @Published var clinicUsers: [AppUser] = []
    @Published var pendingInvitations: [Invitation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let db = Firestore.firestore()
    private let dbService = DatabaseService.shared

    // ══════════════════════════════════════════════════════
    // MARK: - Load clinic users
    // ══════════════════════════════════════════════════════

    func loadUsers(clinicID: String) async {
        await MainActor.run { isLoading = true }

        do {
            let users = try await dbService.getClinicUsers(clinicID: clinicID)
            await MainActor.run {
                self.clinicUsers = users.sorted {
                    $0.displayName < $1.displayName
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }

        // Also load pending invitations
        await loadInvitations(clinicID: clinicID)

        await MainActor.run { isLoading = false }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load pending invitations
    // ══════════════════════════════════════════════════════

    func loadInvitations(clinicID: String) async {
        do {
            let snapshot = try await db.collection("invitations")
                .whereField("clinicID", isEqualTo: clinicID)
                .whereField("status", isEqualTo: "pending")
                .getDocuments()

            let invites = snapshot.documents.compactMap {
                try? $0.data(as: Invitation.self)
            }

            await MainActor.run {
                self.pendingInvitations = invites.sorted {
                    $0.displayName < $1.displayName
                }
            }
        } catch {
            print("Error loading invitations: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Invite user (replaces addUser)
    // Just saves to Firestore — no Auth account created
    // ══════════════════════════════════════════════════════

    func inviteUser(
        firstName: String,
        lastName: String,
        email: String,
        role: AppUser.UserRole,
        clinicID: String,
        by admin: AppUser
    ) async throws {
        guard PermissionManager.canManageUsers(role: admin.role) else {
            throw UserError.insufficientPermissions
        }

        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        let displayName = "\(firstName) \(lastName)"

        // Check if invitation already exists
        let existing = try await db.collection("invitations")
            .document(normalizedEmail)
            .getDocument()

        if existing.exists {
            let data = existing.data()
            let status = data?["status"] as? String ?? ""
            if status == "pending" {
                throw UserError.alreadyInvited
            }
        }

        // Check if user already exists in this clinic
        let existingUsers = try await db.collection("users")
            .whereField("email", isEqualTo: normalizedEmail)
            .whereField("clinicID", isEqualTo: clinicID)
            .getDocuments()

        if !existingUsers.documents.isEmpty {
            throw UserError.alreadyExists
        }

        // Create the invitation
        try await db.collection("invitations")
            .document(normalizedEmail)
            .setData([
                "email": normalizedEmail,
                "displayName": displayName,
                "role": role.rawValue,
                "clinicID": clinicID,
                "invitedBy": admin.id ?? "",
                "invitedByName": admin.displayName,
                "status": "pending",
                "dateCreated": Timestamp(date: Date()),
            ])

        print("Invitation created for \(normalizedEmail)")

        // Log it
        try await dbService.addLog([
            "itemID": normalizedEmail,
            "itemName": displayName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "clinicID": clinicID,
            "action": "userCreated",
            "details": "Invited \(displayName) as \(role.displayName)",
            "previousValue": "",
            "newValue": role.rawValue,
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        await MainActor.run {
            self.successMessage = "Invitation sent! Tell \(firstName) to download the app and sign in with \(normalizedEmail)."
        }

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Check & accept invitation
    // Called after ANY sign-in (email, Google, Apple)
    // ══════════════════════════════════════════════════════

    static func checkAndAcceptInvitation(
        uid: String,
        email: String,
        displayName: String
    ) async -> Bool {
        let db = Firestore.firestore()
        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        do {
            let inviteDoc = try await db.collection("invitations")
                .document(normalizedEmail)
                .getDocument()

            guard let data = inviteDoc.data(),
                  data["status"] as? String == "pending",
                  let role = data["role"] as? String,
                  let clinicID = data["clinicID"] as? String
            else {
                return false
            }

            // Use the invitation's display name if available
            let inviteName = data["displayName"] as? String ?? displayName

            // Create the user profile
            try await db.collection("users").document(uid).setData([
                "email": normalizedEmail,
                "displayName": inviteName,
                "role": role,
                "clinicID": clinicID,
                "phone": "",
                "isActive": true,
                "lastLogin": Timestamp(date: Date()),
                "dateCreated": Timestamp(date: Date())
            ])

            // Mark invitation as accepted
            try await db.collection("invitations")
                .document(normalizedEmail)
                .updateData([
                    "status": "accepted",
                    "dateAccepted": Timestamp(date: Date()),
                    "acceptedUID": uid
                ])

            print("Invitation accepted: \(normalizedEmail) → \(uid)")
            return true

        } catch {
            print("Invitation check error: \(error)")
            return false
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Cancel invitation
    // ══════════════════════════════════════════════════════

    func cancelInvitation(
        email: String,
        clinicID: String,
        by admin: AppUser
    ) async throws {
        guard PermissionManager.canManageUsers(role: admin.role) else {
            throw UserError.insufficientPermissions
        }

        let normalizedEmail = email.lowercased()

        try await db.collection("invitations")
            .document(normalizedEmail)
            .delete()

        print("Invitation cancelled: \(normalizedEmail)")

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Update user role
    // ══════════════════════════════════════════════════════

    func updateUserRole(
        userID: String,
        newRole: AppUser.UserRole,
        clinicID: String,
        by admin: AppUser
    ) async throws {
        guard PermissionManager.canManageUsers(role: admin.role) else {
            throw UserError.insufficientPermissions
        }

        try await dbService.updateUser(
            userID: userID,
            data: ["role": newRole.rawValue]
        )

        let userName = clinicUsers.first(where: { $0.id == userID })?.displayName ?? "Unknown"

        try await dbService.addLog([
            "itemID": userID,
            "itemName": userName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "clinicID": clinicID,
            "action": "userUpdated",
            "details": "Changed \(userName)'s role to \(newRole.displayName)",
            "previousValue": "",
            "newValue": newRole.rawValue,
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Deactivate user
    // ══════════════════════════════════════════════════════

    func deactivateUser(
        userID: String,
        clinicID: String,
        by admin: AppUser
    ) async throws {
        guard PermissionManager.canManageUsers(role: admin.role) else {
            throw UserError.insufficientPermissions
        }

        try await dbService.updateUser(
            userID: userID,
            data: ["isActive": false]
        )

        let userName = clinicUsers.first(where: { $0.id == userID })?.displayName ?? "Unknown"

        try await dbService.addLog([
            "itemID": userID,
            "itemName": userName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "clinicID": clinicID,
            "action": "userUpdated",
            "details": "Deactivated \(userName)",
            "previousValue": "active",
            "newValue": "inactive",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Reactivate user
    // ══════════════════════════════════════════════════════

    func reactivateUser(
        userID: String,
        clinicID: String,
        by admin: AppUser
    ) async throws {
        guard PermissionManager.canManageUsers(role: admin.role) else {
            throw UserError.insufficientPermissions
        }

        try await dbService.updateUser(
            userID: userID,
            data: ["isActive": true]
        )

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Errors
    // ══════════════════════════════════════════════════════

    enum UserError: LocalizedError {
        case insufficientPermissions
        case userNotFound
        case alreadyInvited
        case alreadyExists

        var errorDescription: String? {
            switch self {
            case .insufficientPermissions:
                return "Only admins can manage users."
            case .userNotFound:
                return "User not found."
            case .alreadyInvited:
                return "This email already has a pending invitation."
            case .alreadyExists:
                return "A user with this email already exists in your clinic."
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Invitation Model
// ══════════════════════════════════════════════════════

struct Invitation: Codable, Identifiable {
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
}
