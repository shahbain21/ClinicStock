//
//  AuthManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices
import CryptoKit

@MainActor
class AuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var currentUser: AppUser?
    @Published var currentClinic: Clinic?
    @Published var errorMessage: String?

    // Platform admins pick a clinic per session. Persisted to UserDefaults
    // so the selection survives app restarts.
    @Published var selectedClinicID: String? = nil {
        didSet {
            if let clinicID = selectedClinicID {
                UserDefaults.standard.set(clinicID, forKey: Self.selectedClinicKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedClinicKey)
            }
        }
    }

    // When true, the platform admin sees aggregate data across all clinics.
    // effectiveClinicID returns nil in this mode.
    @Published var isAggregateMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isAggregateMode, forKey: Self.aggregateModeKey)
        }
    }

    /// Resolves the clinic ID for data queries.
    /// Returns nil for platform admins who haven't selected a clinic or are in aggregate mode.
    var effectiveClinicID: String? {
        if let user = currentUser, user.isPlatformAdmin {
            if isAggregateMode { return nil }
            return selectedClinicID
        }
        return currentUser?.clinicID
    }

    var isPlatformAdmin: Bool {
        currentUser?.isPlatformAdmin ?? false
    }

    /// True when a platform admin is logged in but hasn't selected a clinic or aggregate mode.
    var needsClinicSelection: Bool {
        isPlatformAdmin && selectedClinicID == nil && !isAggregateMode
    }

    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    private static let savedEmailKey = "savedEmail"
    private static let selectedClinicKey = "selectedClinicID"
    private static let aggregateModeKey = "isAggregateMode"

    // MARK: - Init

    init(skipListener: Bool = false) {
        if !skipListener {
            listenForAuthChanges()
        } else {
            isLoading = false
        }
    }

    deinit {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }

    // MARK: - Auth State Listener

    // Single source of truth for profile loading. Sign-in methods only
    // call the Firebase API — the listener fires and loads the profile.
    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self = self else { return }
            if let firebaseUser = firebaseUser {
                Task { @MainActor in await self.loadUserProfile(uid: firebaseUser.uid) }
            } else {
                Task { @MainActor in
                    self.currentUser = nil
                    self.currentClinic = nil
                    self.selectedClinicID = nil
                    self.isAggregateMode = false
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Public Helpers

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Email / Password Sign In

    func signIn(email: String, password: String) async throws {
        errorMessage = nil
        let result = try await Auth.auth().signIn(
            withEmail: Self.normalizeEmail(email),
            password: password
        )
        try? await db.collection("users")
            .document(result.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        errorMessage = nil

        let rootVC: UIViewController = try await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController
            else { throw AuthError.noRootViewController }
            return rootVC
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else { throw AuthError.missingToken }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        try? await db.collection("users")
            .document(authResult.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])
    }

    // MARK: - Apple Sign In

    func createAppleSignInRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return request
    }

    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws {
        errorMessage = nil
        let nonce = currentNonce
        currentNonce = nil

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = nonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8)
            else { throw AuthError.missingToken }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            try? await db.collection("users")
                .document(authResult.user.uid)
                .updateData(["lastLogin": Timestamp(date: Date())])

        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            throw error
        }
    }

    // MARK: - Join Clinic (invited user)

    // Creates an Auth account for the invitee, checks for a matching invitation,
    // and provisions their profile. If no invitation is found the Auth account is
    // deleted so they can retry after asking their admin.
    //
    // If the account already exists (a previous join attempt left an orphan),
    // we sign in instead — so a stuck invitee can finish in one tap.
    func joinClinic(email: String, password: String) async throws {
        errorMessage = nil
        let normalizedEmail = Self.normalizeEmail(email)
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            throw AuthError.invalidJoinInput
        }

        let uid: String
        do {
            let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            uid = result.user.uid
        } catch let error as NSError where error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
            let result = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
            uid = result.user.uid
        }

        let accepted = await UserManager.checkAndAcceptInvitation(
            uid: uid, email: normalizedEmail, displayName: "User"
        )

        if accepted { return }

        try? await Auth.auth().currentUser?.delete()
        try? Auth.auth().signOut()
        throw AuthError.noInvitation
    }

    // MARK: - Load User Profile

    // Called only by the auth state listener.
    private func loadUserProfile(uid: String) async {
        do {
            let userDoc = try await db.collection("users").document(uid).getDocument()

            if let user = try? userDoc.data(as: AppUser.self) {
                guard user.isActive else {
                    try? Auth.auth().signOut()
                    self.isAuthenticated = false
                    self.isLoading = false
                    self.errorMessage = "Your account has been deactivated."
                    return
                }

                self.currentUser = user

                if user.isPlatformAdmin {
                    let restored = UserDefaults.standard.string(forKey: Self.selectedClinicKey)
                    let restoredAggregate = UserDefaults.standard.bool(forKey: Self.aggregateModeKey)
                    self.selectedClinicID = restored
                    self.isAggregateMode = restoredAggregate
                    if let clinicID = restored { await loadCurrentClinic(clinicID: clinicID) }
                    else { self.currentClinic = nil }
                } else if let clinicID = user.clinicID {
                    await loadCurrentClinic(clinicID: clinicID)
                }

                self.isAuthenticated = true
                self.isLoading = false
                self.errorMessage = nil
                return
            }

            // No profile — check for an invitation
            let email = Self.normalizeEmail(Auth.auth().currentUser?.email ?? "")
            let accepted = await UserManager.checkAndAcceptInvitation(
                uid: uid, email: email,
                displayName: Auth.auth().currentUser?.displayName ?? "User"
            )

            if accepted {
                await loadUserProfile(uid: uid)
                return
            }

            try? Auth.auth().signOut()
            self.isAuthenticated = false
            self.isLoading = false
            self.errorMessage = "No account found. Ask your clinic admin to invite you."

        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Clinic Selection (platform admin)

    func selectClinic(_ clinicID: String) async {
        guard isPlatformAdmin else { return }
        self.isAggregateMode = false
        self.selectedClinicID = clinicID
        await loadCurrentClinic(clinicID: clinicID)
    }

    func selectAggregateMode() {
        guard isPlatformAdmin else { return }
        self.selectedClinicID = nil
        self.currentClinic = nil
        self.isAggregateMode = true
    }

    func clearClinicSelection() {
        guard isPlatformAdmin else { return }
        self.selectedClinicID = nil
        self.currentClinic = nil
        self.isAggregateMode = false
    }

    private func loadCurrentClinic(clinicID: String) async {
        do {
            let doc = try await db.collection("clinics").document(clinicID).getDocument()
            if let clinic = try? doc.data(as: Clinic.self) {
                self.currentClinic = clinic
            }
        } catch {
            print("Failed to load clinic \(clinicID): \(error)")
        }
    }

    // MARK: - Create Clinic (platform admin)

    // Spins up a new clinic doc owned by the calling platform admin.
    // Returns the new clinic ID so the caller can navigate to it.
    func createClinic(
        name: String, address: String, city: String,
        state: String, zip: String, phone: String, email: String
    ) async throws -> String {
        guard isPlatformAdmin, let uid = currentUser?.id else {
            throw AuthError.invalidRegistrationInput
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw AuthError.invalidRegistrationInput }

        let clinicRef = db.collection("clinics").document()
        try await clinicRef.setData([
            "name": trimmedName,
            "address": address.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "state": state.trimmingCharacters(in: .whitespacesAndNewlines),
            "zip": zip.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": Self.normalizeEmail(email),
            "managerID": uid,
            "isActive": true,
            "dateCreated": Timestamp(date: Date())
        ])
        return clinicRef.documentID
    }

    // MARK: - Archive / Restore Clinic (platform admin)

    // Soft-delete: clinic stays in Firestore but is hidden from pickers
    // and the aggregate view. Restoring brings all data back.
    // Admins cannot archive the clinic they are currently viewing.
    func archiveClinic(_ clinicID: String) async throws {
        guard isPlatformAdmin, !clinicID.isEmpty else { throw AuthError.invalidRegistrationInput }
        if selectedClinicID == clinicID { throw ClinicError.cannotArchiveActiveClinic }
        try await db.collection("clinics").document(clinicID).updateData(["isActive": false])
    }

    func restoreClinic(_ clinicID: String) async throws {
        guard isPlatformAdmin, !clinicID.isEmpty else { throw AuthError.invalidRegistrationInput }
        try await db.collection("clinics").document(clinicID).updateData(["isActive": true])
    }

    enum ClinicError: LocalizedError {
        case cannotArchiveActiveClinic
        var errorDescription: String? {
            "Switch to a different clinic before archiving this one."
        }
    }

    // MARK: - Register New Clinic

    func registerClinic(
        firstName: String, lastName: String,
        organizationName: String, location: String,
        email: String, password: String
    ) async throws {
        errorMessage = nil

        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = Self.normalizeEmail(email)

        guard !trimmedFirst.isEmpty, !trimmedLast.isEmpty,
              !trimmedOrg.isEmpty, !trimmedLocation.isEmpty,
              !normalizedEmail.isEmpty
        else { throw AuthError.invalidRegistrationInput }

        let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
        let uid = result.user.uid

        do {
            let clinicRef = db.collection("clinics").document()
            let clinicID = clinicRef.documentID
            let userRef = db.collection("users").document(uid)
            let batch = db.batch()

            batch.setData([
                "name": trimmedOrg, "address": trimmedLocation,
                "city": "", "state": "", "zip": "", "phone": "",
                "email": normalizedEmail, "managerID": uid,
                "isActive": true, "dateCreated": Timestamp(date: Date())
            ], forDocument: clinicRef)

            batch.setData([
                "email": normalizedEmail,
                "displayName": "\(trimmedFirst) \(trimmedLast)",
                "role": "admin", "clinicID": clinicID, "phone": "",
                "isActive": true, "lastLogin": Timestamp(date: Date()),
                "dateCreated": Timestamp(date: Date())
            ], forDocument: userRef)

            try await batch.commit()
            await seedDefaultSettingsIfMissing()
        } catch {
            try? await result.user.delete()
            try? Auth.auth().signOut()
            throw error
        }
    }

    private func seedDefaultSettingsIfMissing() async {
        let categoriesRef = db.collection("settings").document("categories")
        let sizesRef = db.collection("settings").document("sizes")
        do {
            let catDoc = try await categoriesRef.getDocument()
            if !catDoc.exists {
                try? await categoriesRef.setData(["list": [
                    "Orthopedic", "Cervical", "Lumbar", "Wound Care",
                    "Respiratory", "Diabetic Supplies", "Compression",
                    "Mobility Aids", "Electrical Stimulation", "General Medical"
                ]])
            }
            let sizesDoc = try await sizesRef.getDocument()
            if !sizesDoc.exists {
                try? await sizesRef.setData(["list": [
                    "XS", "S", "M", "L", "XL", "XXL",
                    "Universal", "Pediatric", "Custom", "N/A", "RT", "LT"
                ]])
            }
        } catch {
            print("Default settings seed check failed: \(error)")
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
            currentClinic = nil
            selectedClinicID = nil
            isAggregateMode = false
            isAuthenticated = false
            isLoading = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reset Password

    func resetPassword(email: String) async throws {
        errorMessage = nil
        try await Auth.auth().sendPasswordReset(withEmail: Self.normalizeEmail(email))
    }

    // MARK: - Remembered Email

    var savedEmail: String? { UserDefaults.standard.string(forKey: Self.savedEmailKey) }
    var hasRememberedEmail: Bool { savedEmail != nil }

    func rememberEmail(_ email: String) {
        let normalized = Self.normalizeEmail(email)
        if normalized.isEmpty { forgetEmail(); return }
        UserDefaults.standard.set(normalized, forKey: Self.savedEmailKey)
    }

    func forgetEmail() {
        UserDefaults.standard.removeObject(forKey: Self.savedEmailKey)
    }

    // MARK: - Helpers

    private static func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess { fatalError("Unable to generate nonce.") }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    private func buildDisplayName(from fullName: PersonNameComponents?, fallback: String?) -> String {
        if let fullName {
            let combined = "\(fullName.givenName ?? "") \(fullName.familyName ?? "")".trimmingCharacters(in: .whitespaces)
            if !combined.isEmpty { return combined }
        }
        return fallback ?? "User"
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case noRootViewController
        case missingToken
        case invalidRegistrationInput
        case invalidJoinInput
        case noInvitation

        var errorDescription: String? {
            switch self {
            case .noRootViewController: return "Unable to find root view controller."
            case .missingToken: return "Authentication failed. Please try again."
            case .invalidRegistrationInput: return "Please fill in all registration fields."
            case .invalidJoinInput: return "Please enter a valid email."
            case .noInvitation: return "No invitation found for this email. Ask your clinic admin to invite you first."
            }
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension AuthManager {
    static func preview(
        isAuthenticated: Bool = false,
        currentUser: AppUser? = nil,
        currentClinic: Clinic? = nil
    ) -> AuthManager {
        let manager = AuthManager(skipListener: true)
        manager.isAuthenticated = isAuthenticated
        manager.currentUser = currentUser
        manager.currentClinic = currentClinic
        manager.isLoading = false
        return manager
    }
}
#endif
