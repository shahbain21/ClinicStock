//
//  AuthManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  FIXES (this pass):
//  - joinClinic(email:password:) added. Centralizes the invitation
//    acceptance flow (was previously duplicated inside JoinClinicView).
//    Creates the Auth account, lets the auth listener check for an
//    invitation and provision the profile, rolls back the Auth account
//    if no invitation is found.
//  - clearError() helper so views don't need to mutate errorMessage.
//
//  EARLIER FIXES (carried forward):
//  - Registration writes are transactional with Auth rollback on failure.
//  - Settings seeded only if missing (no cross-clinic stomping).
//  - Auth listener is the single source of truth; sign-in methods don't
//    manually call loadUserProfile.
//  - Email normalized (trimmed + lowercased) at every entry point.
//  - currentNonce cleared after use.
//  - Remembered-email persistence via manager methods, not magic strings.
//  - Defensive input validation in registerClinic.
//  - @MainActor on the class.
//  - Preview-safe init.
//  - Nonce charset includes 'W' (was missing).
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

    // Platform-admin session state.
    //
    // For a platform admin (role == .admin, clinicID == nil), this is
    // the clinic they're currently "acting as" during this session. For
    // everyone else it's ignored — use `effectiveClinicID` to resolve.
    //
    // Persisted to UserDefaults so an admin doesn't have to re-pick on
    // every app launch.
    @Published var selectedClinicID: String? = nil {
        didSet {
            if let clinicID = selectedClinicID {
                UserDefaults.standard.set(clinicID, forKey: Self.selectedClinicKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.selectedClinicKey)
            }
        }
    }

    /// Platform admin "All Clinics" view. When true, the admin is in
    /// aggregate mode — viewing data summed across all clinics rather
    /// than scoped to one. effectiveClinicID returns nil in this mode,
    /// so any view that requires a specific clinic context (Add Item,
    /// Scan, etc.) should disable its write actions.
    @Published var isAggregateMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isAggregateMode, forKey: Self.aggregateModeKey)
        }
    }

    /// The clinic ID to use for data queries. For platform admins this
    /// is whatever they selected from the clinic picker. For everyone
    /// else it's their own clinicID (they have no choice).
    ///
    /// Returns nil for:
    ///   - A platform admin who hasn't selected a clinic yet
    ///   - A platform admin in aggregate "All Clinics" mode
    ///   - A non-admin user whose profile has no clinicID (shouldn't
    ///     happen — defensive)
    var effectiveClinicID: String? {
        if let user = currentUser, user.isPlatformAdmin {
            if isAggregateMode { return nil }
            return selectedClinicID
        }
        return currentUser?.clinicID
    }

    /// Convenience — true when the current user is a platform admin.
    var isPlatformAdmin: Bool {
        return currentUser?.isPlatformAdmin ?? false
    }

    /// True when a platform admin is logged in but hasn't picked a
    /// clinic OR aggregate mode yet. RootView uses this to route to
    /// the picker.
    var needsClinicSelection: Bool {
        return isPlatformAdmin && selectedClinicID == nil && !isAggregateMode
    }

    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?

    // Apple Sign-In requires a nonce. Nil when no Apple sign-in is in flight.
    private var currentNonce: String?

    private static let savedEmailKey = "savedEmail"
    private static let selectedClinicKey = "selectedClinicID"
    private static let aggregateModeKey = "isAggregateMode"

    // ══════════════════════════════════════════════════════
    // MARK: - Init
    // ══════════════════════════════════════════════════════

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

    // ══════════════════════════════════════════════════════
    // MARK: - Auth State Listener
    //
    // Single source of truth for profile loading. Sign-in methods only
    // call the Firebase API — the listener fires, profile gets loaded,
    // @Published state updates.
    // ══════════════════════════════════════════════════════

    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener {
            [weak self] _, firebaseUser in

            guard let self = self else { return }

            if let firebaseUser = firebaseUser {
                print("User detected: \(firebaseUser.uid)")
                Task { @MainActor in
                    await self.loadUserProfile(uid: firebaseUser.uid)
                }
            } else {
                print("No user logged in")
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

    // ══════════════════════════════════════════════════════
    // MARK: - Clear error (for views)
    // ══════════════════════════════════════════════════════

    func clearError() {
        errorMessage = nil
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Email / Password Sign In
    // ══════════════════════════════════════════════════════

    func signIn(email: String, password: String) async throws {
        errorMessage = nil
        let normalizedEmail = Self.normalizeEmail(email)

        let result = try await Auth.auth().signIn(
            withEmail: normalizedEmail,
            password: password
        )
        print("Signed in: \(result.user.uid)")

        try? await db.collection("users")
            .document(result.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])

        // Auth listener handles profile loading.
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Google Sign In
    // ══════════════════════════════════════════════════════

    func signInWithGoogle() async throws {
        errorMessage = nil

        let rootVC: UIViewController = try await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController
            else {
                throw AuthError.noRootViewController
            }
            return rootVC
        }

        let result: GIDSignInResult = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootVC
        )

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingToken
        }
        let accessToken = result.user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        print("Google sign-in: \(authResult.user.uid)")

        try? await db.collection("users")
            .document(authResult.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Apple Sign In
    // ══════════════════════════════════════════════════════

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

        // Grab and clear the nonce up front so it can never be reused.
        let nonce = currentNonce
        currentNonce = nil

        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = nonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8)
            else {
                throw AuthError.missingToken
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            print("Apple sign-in: \(authResult.user.uid)")

            try? await db.collection("users")
                .document(authResult.user.uid)
                .updateData(["lastLogin": Timestamp(date: Date())])

        case .failure(let error):
            // User cancelled — don't show error
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            throw error
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Join Clinic (invited user, email/password path)
    //
    // Creates a Firebase Auth account for an invited user, then lets the
    // auth listener check for the invitation and provision the profile.
    // If no invitation is found for the email, the Auth account is
    // deleted so the user can retry (e.g., after asking their admin to
    // invite them).
    // ══════════════════════════════════════════════════════

    func joinClinic(email: String, password: String) async throws {
        errorMessage = nil
        let normalizedEmail = Self.normalizeEmail(email)

        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            throw AuthError.invalidJoinInput
        }

        // Try to create an Auth account. If that fails because the
        // account already exists (which happens when a prior Join
        // attempt failed and left an orphaned Auth account behind —
        // see comment on the rollback below), try signing in instead.
        // The same password they're typing now should work as long as
        // it matches what they used last time.
        //
        // This recovery means an invitee who got stuck partway through
        // a previous attempt can finish the Join in one tap rather than
        // needing Forgot Password or admin intervention.
        let uid: String
        do {
            let result = try await Auth.auth().createUser(
                withEmail: normalizedEmail,
                password: password
            )
            uid = result.user.uid
            print("Join: new auth account created \(uid)")
        } catch let error as NSError where error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
            print("Join: auth account exists, trying sign-in")
            let result = try await Auth.auth().signIn(
                withEmail: normalizedEmail,
                password: password
            )
            uid = result.user.uid
            print("Join: signed into existing auth account \(uid)")
        }

        // Check for an invitation
        let accepted = await UserManager.checkAndAcceptInvitation(
            uid: uid,
            email: normalizedEmail,
            displayName: "User"
        )

        if accepted {
            print("Join: invitation accepted, listener will pick up profile")
            // The auth listener will reload the profile and flip
            // isAuthenticated. The view just needs to dismiss.
            return
        }

        // No invitation — try to roll back. Note this is best-effort:
        // Firebase requires recent authentication for delete(), and
        // depending on timing this can silently fail. Failed rollback
        // means a stale Auth account stays in Firebase, which is why
        // we have the createUser-or-signIn fallback above.
        print("Join: no invitation found, attempting auth account rollback")
        try? await Auth.auth().currentUser?.delete()
        try? Auth.auth().signOut()

        throw AuthError.noInvitation
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load User Profile
    //
    // Called ONLY by the auth state listener.
    // ══════════════════════════════════════════════════════

    private func loadUserProfile(uid: String) async {
        do {
            let userDoc = try await db.collection("users")
                .document(uid)
                .getDocument()

            if let user = try? userDoc.data(as: AppUser.self) {

                guard user.isActive else {
                    print("User is deactivated")
                    try? Auth.auth().signOut()
                    self.isAuthenticated = false
                    self.isLoading = false
                    self.errorMessage = "Your account has been deactivated."
                    return
                }

                self.currentUser = user

                // Branch on user type:
                //   Platform admin (clinicID == nil):
                //     Restore any previously-selected clinic from
                //     UserDefaults. If none, RootView will route to
                //     ClinicPickerView via needsClinicSelection.
                //   Clinic user (clinicID set):
                //     Load their single clinic as always.
                if user.isPlatformAdmin {
                    let restored = UserDefaults.standard.string(
                        forKey: Self.selectedClinicKey
                    )
                    let restoredAggregate = UserDefaults.standard.bool(
                        forKey: Self.aggregateModeKey
                    )
                    self.selectedClinicID = restored
                    self.isAggregateMode = restoredAggregate

                    if let clinicID = restored {
                        await loadCurrentClinic(clinicID: clinicID)
                    } else {
                        self.currentClinic = nil
                    }
                } else if let clinicID = user.clinicID {
                    await loadCurrentClinic(clinicID: clinicID)
                }

                self.isAuthenticated = true
                self.isLoading = false
                self.errorMessage = nil

                print("Profile loaded:")
                print("   Name: \(user.displayName)")
                print("   Role: \(user.role.rawValue)")
                print("   Clinic: \(self.currentClinic?.name ?? (user.isPlatformAdmin ? "[platform admin, no selection]" : "Unknown"))")
                return
            }

            // Profile doesn't exist — check for invitation
            let email = Self.normalizeEmail(Auth.auth().currentUser?.email ?? "")
            print("No profile found. Checking invitation for: \(email)")

            let accepted = await UserManager.checkAndAcceptInvitation(
                uid: uid,
                email: email,
                displayName: Auth.auth().currentUser?.displayName ?? "User"
            )

            if accepted {
                print("Invitation accepted — loading profile")
                await loadUserProfile(uid: uid)
                return
            }

            print("No profile or invitation found")
            try? Auth.auth().signOut()
            self.isAuthenticated = false
            self.isLoading = false
            self.errorMessage = "No account found. Ask your clinic admin to invite you."

        } catch {
            print("Error loading profile: \(error)")
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Clinic Selection (platform admin)
    //
    // Platform admins don't have a clinicID on their user record;
    // instead they pick one per session from the available clinics.
    // These helpers persist the selection + load the clinic doc.
    // ══════════════════════════════════════════════════════

    /// Set the active clinic for a platform admin and load its doc.
    /// Silently no-ops for non-admin users (they can't switch clinics).
    func selectClinic(_ clinicID: String) async {
        guard isPlatformAdmin else {
            print("selectClinic called by non-platform-admin — ignoring")
            return
        }
        self.isAggregateMode = false
        self.selectedClinicID = clinicID
        await loadCurrentClinic(clinicID: clinicID)
    }

    /// Enter aggregate "All Clinics" mode for a platform admin.
    /// Inventory listener stops, dashboard switches to cross-clinic
    /// summary, write actions in single-clinic views become disabled.
    func selectAggregateMode() {
        guard isPlatformAdmin else {
            print("selectAggregateMode called by non-platform-admin — ignoring")
            return
        }
        self.selectedClinicID = nil
        self.currentClinic = nil
        self.isAggregateMode = true
    }

    /// Clear the platform admin's clinic selection. Sends them back to
    /// the clinic picker on next render.
    func clearClinicSelection() {
        guard isPlatformAdmin else { return }
        self.selectedClinicID = nil
        self.currentClinic = nil
        self.isAggregateMode = false
    }

    /// Fetch a Clinic document and publish it as currentClinic.
    /// Safe to call from any authenticated context — does nothing on
    /// failure (leaves currentClinic at its prior value).
    private func loadCurrentClinic(clinicID: String) async {
        do {
            let clinicDoc = try await db.collection("clinics")
                .document(clinicID)
                .getDocument()
            if let clinic = try? clinicDoc.data(as: Clinic.self) {
                self.currentClinic = clinic
            } else {
                print("Clinic doc exists but couldn't decode: \(clinicID)")
            }
        } catch {
            print("Failed to load clinic \(clinicID): \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Create New Clinic (platform admin only)
    //
    // Adds a new clinic doc owned by the calling platform admin. Unlike
    // registerClinic (which creates clinic + admin in one Auth account
    // creation), this assumes the admin already exists and just spins
    // up another location.
    //
    // The new clinic has no users initially. The admin can invite a
    // manager / staff once they're inside the clinic. (User-creation
    // is intentionally separate to keep this flow simple.)
    //
    // Returns the new clinic's ID so callers can navigate to it or
    // offer "switch to this clinic now?".
    // ══════════════════════════════════════════════════════

    func createClinic(
        name: String,
        address: String,
        city: String,
        state: String,
        zip: String,
        phone: String,
        email: String
    ) async throws -> String {
        guard isPlatformAdmin else {
            throw AuthError.invalidRegistrationInput
        }
        guard let uid = currentUser?.id else {
            throw AuthError.invalidRegistrationInput
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthError.invalidRegistrationInput
        }

        let clinicRef = db.collection("clinics").document()
        let clinicID = clinicRef.documentID

        try await clinicRef.setData([
            "name": trimmedName,
            "address": address.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "state": state.trimmingCharacters(in: .whitespacesAndNewlines),
            "zip": zip.trimmingCharacters(in: .whitespacesAndNewlines),
            "phone": phone.trimmingCharacters(in: .whitespacesAndNewlines),
            "email": Self.normalizeEmail(email),
            // managerID points at the platform admin so the rules' create
            // check passes. The admin isn't actually "manager" in role
            // terms — they're platform admin owning this clinic.
            "managerID": uid,
            "isActive": true,
            "dateCreated": Timestamp(date: Date())
        ])

        print("Platform admin created new clinic: \(clinicID)")
        return clinicID
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Archive / Restore Clinic (platform admin only)
    //
    // Soft-delete pattern: the clinic doc stays in Firestore but is
    // hidden from the picker, the All Clinics aggregate view, and
    // any flow that uses getAllClinics(). Archived clinics retain
    // their inventory, history, and users — restore brings them all
    // back without data loss.
    //
    // Hard delete is intentionally NOT supported. Removing a clinic
    // entirely orphans its inventory and history logs, which we
    // want to keep for audit/compliance regardless of operational
    // status.
    //
    // Important constraint: an admin cannot archive the clinic they
    // are currently viewing. They must switch to a different clinic
    // (or All Clinics) first. This prevents the awkward state where
    // the active clinic disappears mid-action.
    // ══════════════════════════════════════════════════════

    func archiveClinic(_ clinicID: String) async throws {
        guard isPlatformAdmin else {
            throw AuthError.invalidRegistrationInput
        }
        guard !clinicID.isEmpty else {
            throw AuthError.invalidRegistrationInput
        }

        // Block archiving the currently-active clinic. Caller (the
        // Manage Clinics screen) should disable the button in this
        // state, but we double-check here as a safety net.
        if selectedClinicID == clinicID {
            throw ClinicError.cannotArchiveActiveClinic
        }

        try await db.collection("clinics")
            .document(clinicID)
            .updateData(["isActive": false])

        print("Archived clinic: \(clinicID)")
    }

    func restoreClinic(_ clinicID: String) async throws {
        guard isPlatformAdmin else {
            throw AuthError.invalidRegistrationInput
        }
        guard !clinicID.isEmpty else {
            throw AuthError.invalidRegistrationInput
        }

        try await db.collection("clinics")
            .document(clinicID)
            .updateData(["isActive": true])

        print("Restored clinic: \(clinicID)")
    }

    /// Errors specific to clinic management actions.
    enum ClinicError: LocalizedError {
        case cannotArchiveActiveClinic

        var errorDescription: String? {
            switch self {
            case .cannotArchiveActiveClinic:
                return "Switch to a different clinic before archiving this one."
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Register New Clinic
    // ══════════════════════════════════════════════════════

    func registerClinic(
        firstName: String,
        lastName: String,
        organizationName: String,
        location: String,
        email: String,
        password: String
    ) async throws {
        errorMessage = nil

        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = Self.normalizeEmail(email)

        guard !trimmedFirst.isEmpty,
              !trimmedLast.isEmpty,
              !trimmedOrg.isEmpty,
              !trimmedLocation.isEmpty,
              !normalizedEmail.isEmpty else {
            throw AuthError.invalidRegistrationInput
        }

        let result = try await Auth.auth().createUser(
            withEmail: normalizedEmail,
            password: password
        )
        let uid = result.user.uid
        print("Auth account created: \(uid)")

        do {
            let clinicRef = db.collection("clinics").document()
            let clinicID = clinicRef.documentID
            let userRef = db.collection("users").document(uid)

            let batch = db.batch()

            batch.setData([
                "name": trimmedOrg,
                "address": trimmedLocation,
                "city": "",
                "state": "",
                "zip": "",
                "phone": "",
                "email": normalizedEmail,
                "managerID": uid,
                "isActive": true,
                "dateCreated": Timestamp(date: Date())
            ], forDocument: clinicRef)

            batch.setData([
                "email": normalizedEmail,
                "displayName": "\(trimmedFirst) \(trimmedLast)",
                "role": "admin",
                "clinicID": clinicID,
                "phone": "",
                "isActive": true,
                "lastLogin": Timestamp(date: Date()),
                "dateCreated": Timestamp(date: Date())
            ], forDocument: userRef)

            try await batch.commit()
            print("Clinic and admin profile committed: \(clinicID)")

            await seedDefaultSettingsIfMissing()

        } catch {
            print("Registration failed, rolling back Auth account: \(error)")
            try? await result.user.delete()
            try? Auth.auth().signOut()
            throw error
        }

        print("Registration complete!")
    }

    private func seedDefaultSettingsIfMissing() async {
        let categoriesRef = db.collection("settings").document("categories")
        let sizesRef = db.collection("settings").document("sizes")

        do {
            let catDoc = try await categoriesRef.getDocument()
            if !catDoc.exists {
                try? await categoriesRef.setData([
                    "list": [
                        "Orthopedic", "Cervical", "Lumbar",
                        "Wound Care", "Respiratory", "Diabetic Supplies",
                        "Compression", "Mobility Aids",
                        "Electrical Stimulation", "General Medical"
                    ]
                ])
            }

            let sizesDoc = try await sizesRef.getDocument()
            if !sizesDoc.exists {
                try? await sizesRef.setData([
                    "list": [
                        "XS", "S", "M", "L", "XL", "XXL",
                        "Universal", "Pediatric", "Custom",
                        "N/A", "RT", "LT"
                    ]
                ])
            }
        } catch {
            print("Default settings seed check failed: \(error)")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Sign Out
    // ══════════════════════════════════════════════════════

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
            currentClinic = nil
            selectedClinicID = nil  // clears UserDefaults via didSet
            isAggregateMode = false
            isAuthenticated = false
            isLoading = false
            errorMessage = nil
            print("Signed out")
        } catch {
            print("Error signing out: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Reset Password
    // ══════════════════════════════════════════════════════

    func resetPassword(email: String) async throws {
        errorMessage = nil
        let normalizedEmail = Self.normalizeEmail(email)
        try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
        print("Password reset email sent to \(normalizedEmail)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Remembered Email Persistence
    // ══════════════════════════════════════════════════════

    var savedEmail: String? {
        UserDefaults.standard.string(forKey: Self.savedEmailKey)
    }

    var hasRememberedEmail: Bool {
        savedEmail != nil
    }

    func rememberEmail(_ email: String) {
        let normalized = Self.normalizeEmail(email)
        guard !normalized.isEmpty else {
            forgetEmail()
            return
        }
        UserDefaults.standard.set(normalized, forKey: Self.savedEmailKey)
    }

    func forgetEmail() {
        UserDefaults.standard.removeObject(forKey: Self.savedEmailKey)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════

    private static func normalizeEmail(_ email: String) -> String {
        return email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Apple Sign-In Nonce Helpers
    // ══════════════════════════════════════════════════════

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(
            kSecRandomDefault,
            randomBytes.count,
            &randomBytes
        )
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce.")
        }
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
    }

    private func buildDisplayName(
        from fullName: PersonNameComponents?,
        fallback: String?
    ) -> String {
        if let fullName = fullName {
            let first = fullName.givenName ?? ""
            let last = fullName.familyName ?? ""
            let combined = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            if !combined.isEmpty { return combined }
        }
        return fallback ?? "User"
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Errors
    // ══════════════════════════════════════════════════════

    enum AuthError: LocalizedError {
        case noRootViewController
        case missingToken
        case invalidRegistrationInput
        case invalidJoinInput
        case noInvitation

        var errorDescription: String? {
            switch self {
            case .noRootViewController:
                return "Unable to find root view controller."
            case .missingToken:
                return "Authentication failed. Please try again."
            case .invalidRegistrationInput:
                return "Please fill in all registration fields."
            case .invalidJoinInput:
                return "Please enter a valid email."
            case .noInvitation:
                return "No invitation found for this email. Ask your clinic admin to invite you first."
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview Support
// ══════════════════════════════════════════════════════

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
