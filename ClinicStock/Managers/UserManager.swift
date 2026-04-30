//
//  UserManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
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
        isLoading = true
        defer { isLoading = false }

        do {
            let users = try await dbService.getClinicUsers(clinicID: clinicID)
            self.clinicUsers = users.sorted { $0.displayName < $1.displayName }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        // Also load pending invitations
        await loadInvitations(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load pending invitations
    // ══════════════════════════════════════════════════════

    func loadInvitations(clinicID: String) async {
        do {
            let invites = try await dbService.getPendingInvitations(clinicID: clinicID)
            self.pendingInvitations = invites.sorted {
                $0.displayName < $1.displayName
            }
        } catch {
            print("Error loading invitations: \(error)")
            // Surface so admin knows invitations list may be incomplete
            self.errorMessage = "Could not load invitations: \(error.localizedDescription)"
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Invite user
    //
    // Just saves to Firestore — no Auth account created. The invitee
    // signs in later via Email/Google/Apple and their profile is
    // auto-provisioned via checkAndAcceptInvitation.
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

        // Defensive input validation
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = Self.normalizeEmail(email)

        guard !trimmedFirst.isEmpty,
              !trimmedLast.isEmpty,
              !normalizedEmail.isEmpty,
              normalizedEmail.contains("@") else {
            throw UserError.invalidInput
        }

        let displayName = "\(trimmedFirst) \(trimmedLast)"

        // Check if invitation already exists and is still pending
        if let existing = try await dbService.getInvitation(email: normalizedEmail),
           existing.isPending {
            throw UserError.alreadyInvited
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
        try await dbService.saveInvitation([
            "email": normalizedEmail,
            "displayName": displayName,
            "role": role.rawValue,
            "clinicID": clinicID,
            "invitedBy": admin.id ?? "",
            "invitedByName": admin.displayName,
            "status": "pending",
            "dateCreated": Timestamp(date: Date())
        ], email: normalizedEmail)

        print("Invitation created for \(normalizedEmail)")

        // Audit log
        try await dbService.addLog([
            "itemID": normalizedEmail,
            "itemName": displayName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "action": "userCreated",
            "details": "Invited \(displayName) as \(role.displayName)",
            "previousValue": "",
            "newValue": role.rawValue,
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        self.successMessage = "Invitation sent! Tell \(trimmedFirst) to download the app and sign in with \(normalizedEmail)."

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Check & accept invitation
    //
    // Called by AuthManager during profile loading, for ANY sign-in
    // method (email, Google, Apple). Static because it's called before
    // any UserManager instance exists — from AuthManager's auth listener.
    //
    // TRUST BOUNDARY: Assumes `uid` and `email` came from Firebase Auth
    // (i.e., the caller has verified ownership of the email). A caller
    // passing arbitrary values here would create a profile for that uid
    // with whatever role the invitation specifies.
    //
    // ATOMICITY: The profile-create and invitation-accept writes commit
    // as a single WriteBatch. Previously these were two separate writes;
    // a failure between them would leave the invitation pending forever
    // while the user had a working profile.
    // ══════════════════════════════════════════════════════

    static func checkAndAcceptInvitation(
        uid: String,
        email: String,
        displayName: String
    ) async -> Bool {
        let normalizedEmail = normalizeEmail(email)
        guard !normalizedEmail.isEmpty else { return false }

        let db = Firestore.firestore()

        do {
            // Fetch the invitation. The doc ID is the raw normalized
            // email (Firestore allows '.' in document IDs).
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

            // Use the invitation's display name if it has one
            let inviteName = data["displayName"] as? String ?? displayName

            // Atomic: create profile + mark invitation accepted in one batch
            let userRef = db.collection("users").document(uid)
            let inviteRef = db.collection("invitations").document(normalizedEmail)

            let batch = db.batch()

            batch.setData([
                "email": normalizedEmail,
                "displayName": inviteName,
                "role": role,
                "clinicID": clinicID,
                "phone": "",
                "isActive": true,
                "lastLogin": Timestamp(date: Date()),
                "dateCreated": Timestamp(date: Date())
            ], forDocument: userRef)

            batch.updateData([
                "status": "accepted",
                "dateAccepted": Timestamp(date: Date()),
                "acceptedUID": uid
            ], forDocument: inviteRef)

            try await batch.commit()

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

        let normalizedEmail = Self.normalizeEmail(email)

        // Capture the invitation's display name before deleting, for the log
        let invitation = try await dbService.getInvitation(email: normalizedEmail)
        let inviteeName = invitation?.displayName ?? normalizedEmail

        try await dbService.deleteInvitation(email: normalizedEmail)

        print("Invitation cancelled: \(normalizedEmail)")

        // Audit log — previously missing
        try await dbService.addLog([
            "itemID": normalizedEmail,
            "itemName": inviteeName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "action": "userUpdated",
            "details": "Cancelled invitation for \(inviteeName)",
            "previousValue": "pending",
            "newValue": "cancelled",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

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

        // Fetch fresh — don't rely on local cache which may be stale/empty
        let targetUser = try await dbService.getUser(userID: userID)
        let userName = targetUser?.displayName ?? "Unknown"
        let previousRole = targetUser?.role.rawValue ?? ""

        try await dbService.updateUser(
            userID: userID,
            data: ["role": newRole.rawValue]
        )

        try await dbService.addLog([
            "itemID": userID,
            "itemName": userName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "action": "userUpdated",
            "details": "Changed \(userName)'s role to \(newRole.displayName)",
            "previousValue": previousRole,
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

        // Fetch fresh
        let targetUser = try await dbService.getUser(userID: userID)
        let userName = targetUser?.displayName ?? "Unknown"

        try await dbService.updateUser(
            userID: userID,
            data: ["isActive": false]
        )

        try await dbService.addLog([
            "itemID": userID,
            "itemName": userName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
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

        let targetUser = try await dbService.getUser(userID: userID)
        let userName = targetUser?.displayName ?? "Unknown"

        try await dbService.updateUser(
            userID: userID,
            data: ["isActive": true]
        )

        // Log reactivation for audit completeness (previously unlogged)
        try await dbService.addLog([
            "itemID": userID,
            "itemName": userName,
            "itemBarcode": "",
            "userID": admin.id ?? "",
            "userName": admin.displayName,
            "action": "userUpdated",
            "details": "Reactivated \(userName)",
            "previousValue": "inactive",
            "newValue": "active",
            "timestamp": Timestamp(date: Date())
        ], clinicID: clinicID)

        await loadUsers(clinicID: clinicID)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════

    /// Shared email normalizer used by both instance and static methods.
    static func normalizeEmail(_ email: String) -> String {
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Errors
    // ══════════════════════════════════════════════════════

    enum UserError: LocalizedError {
        case insufficientPermissions
        case userNotFound
        case alreadyInvited
        case alreadyExists
        case invalidInput

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
            case .invalidInput:
                return "Please enter a first name, last name, and valid email."
            }
        }
    }
}
