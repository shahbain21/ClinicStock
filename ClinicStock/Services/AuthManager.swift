//
//  AuthManager.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/3/26.
//
//  UPDATED:
//  - Added Google Sign-In
//  - Added Apple Sign-In
//  - Remember Me loads saved email
//  - Shared sign-in completion handler for all providers
//
//  FIXES:
//  - Preview-safe init: pass skipListener: true to avoid Firebase in #Preview
//  - AuthManager.preview() factory for SwiftUI previews
//  - Fixed nonce charset typo (missing 'W')
//  - signOut() now resets isLoading for consistent UI state
//  - Removed unused parameters from handleSocialSignIn
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices
import CryptoKit

class AuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var currentUser: AppUser?
    @Published var currentClinic: Clinic?
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var authListener: AuthStateDidChangeListenerHandle?

    // Apple Sign-In requires a nonce for security
    private var currentNonce: String?

    // ══════════════════════════════════════════════════════
    // MARK: - Init
    //
    // Pass skipListener: true from SwiftUI #Preview blocks to prevent
    // AuthManager from touching Firebase (which isn't configured in previews).
    // ══════════════════════════════════════════════════════

    init(skipListener: Bool = false) {
        if !skipListener {
            listenForAuthChanges()
        } else {
            // Previews don't have Firebase — don't pretend we're loading.
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
    // ══════════════════════════════════════════════════════

    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener {
            [weak self] _, firebaseUser in

            guard let self = self else { return }

            if let firebaseUser = firebaseUser {
                print("User detected: \(firebaseUser.uid)")
                Task {
                    await self.loadUserProfile(uid: firebaseUser.uid)
                }
            } else {
                print("No user logged in")
                DispatchQueue.main.async {
                    self.currentUser = nil
                    self.currentClinic = nil
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Email / Password Sign In
    // ══════════════════════════════════════════════════════

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(
            withEmail: email,
            password: password
        )
        print("Signed in: \(result.user.uid)")

        try? await db.collection("users")
            .document(result.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])

        await loadUserProfile(uid: result.user.uid)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Google Sign In
    // ══════════════════════════════════════════════════════

    func signInWithGoogle() async throws {
        // Get the root view controller
        let rootVC: UIViewController = try await MainActor.run {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController
            else {
                throw AuthError.noRootViewController
            }
            return rootVC
        }

        // Start Google Sign-In flow
        let result: GIDSignInResult = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootVC
        )

        // Get tokens
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingToken
        }
        let accessToken = result.user.accessToken.tokenString

        // Create Firebase credential
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        // Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        print("Google sign-in: \(authResult.user.uid)")

        await handleSocialSignIn(uid: authResult.user.uid)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Apple Sign In
    // ══════════════════════════════════════════════════════

    // Step 1: Generate nonce and create the Apple request
    func createAppleSignInRequest() -> ASAuthorizationAppleIDRequest {
        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        return request
    }

    // Step 2: Handle the Apple Sign-In result
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce,
                  let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8)
            else {
                throw AuthError.missingToken
            }

            // Create Firebase credential
            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            // Sign in to Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            print("Apple sign-in: \(authResult.user.uid)")

            await handleSocialSignIn(uid: authResult.user.uid)

        case .failure(let error):
            // User cancelled — don't show error
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            throw error
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load User Profile
    // Now checks for invitations if profile doesn't exist
    // ══════════════════════════════════════════════════════

    private func loadUserProfile(uid: String) async {
        do {
            let userDoc = try await db.collection("users")
                .document(uid)
                .getDocument()

            // Profile exists — load it
            if let user = try? userDoc.data(as: AppUser.self) {

                guard user.isActive else {
                    print("User is deactivated")
                    try? Auth.auth().signOut()
                    await MainActor.run {
                        self.isAuthenticated = false
                        self.isLoading = false
                        self.errorMessage = "Your account has been deactivated."
                    }
                    return
                }

                let clinicDoc = try await db.collection("clinics")
                    .document(user.clinicID)
                    .getDocument()
                let clinic = try? clinicDoc.data(as: Clinic.self)

                await MainActor.run {
                    self.currentUser = user
                    self.currentClinic = clinic
                    self.isAuthenticated = true
                    self.isLoading = false
                    self.errorMessage = nil

                    print("Profile loaded:")
                    print("   Name: \(user.displayName)")
                    print("   Role: \(user.role.rawValue)")
                    print("   Clinic: \(clinic?.name ?? "Unknown")")
                }
                return
            }

            // Profile doesn't exist — check for invitation
            let email = Auth.auth().currentUser?.email ?? ""
            print("No profile found. Checking invitation for: \(email)")

            let accepted = await UserManager.checkAndAcceptInvitation(
                uid: uid,
                email: email,
                displayName: Auth.auth().currentUser?.displayName ?? "User"
            )

            if accepted {
                print("Invitation accepted — loading profile")
                // Profile was just created from invitation — load it
                await loadUserProfile(uid: uid)
                return
            }

            // No profile AND no invitation
            print("No profile or invitation found")
            try? Auth.auth().signOut()
            await MainActor.run {
                self.isAuthenticated = false
                self.isLoading = false
                self.errorMessage = "No account found. Ask your clinic admin to invite you."
            }

        } catch {
            print("Error loading profile: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Shared Social Sign-In Handler
    // Simplified — just loads profile (which checks invitations)
    // ══════════════════════════════════════════════════════

    private func handleSocialSignIn(uid: String) async {
        // Update last login if user exists (no-op if doc doesn't exist yet)
        try? await db.collection("users")
            .document(uid)
            .updateData(["lastLogin": Timestamp(date: Date())])

        // loadUserProfile handles everything:
        // - Existing profile → sign in
        // - No profile but invitation exists → accept invitation → sign in
        // - No profile and no invitation → reject
        await loadUserProfile(uid: uid)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Register New Clinic
    // Creates Auth account + Clinic + Admin user profile
    // ══════════════════════════════════════════════════════

    func registerClinic(
        firstName: String,
        lastName: String,
        organizationName: String,
        location: String,
        email: String,
        password: String
    ) async throws {

        // 1. Create Firebase Auth account
        let result = try await Auth.auth().createUser(
            withEmail: email,
            password: password
        )

        let uid = result.user.uid
        print("Auth account created: \(uid)")

        // 2. Create the clinic
        let clinicRef = db.collection("clinics").document()
        let clinicID = clinicRef.documentID

        try await clinicRef.setData([
            "name": organizationName,
            "address": location,
            "city": "",
            "state": "",
            "zip": "",
            "phone": "",
            "email": email,
            "managerID": uid,
            "isActive": true,
            "dateCreated": Timestamp(date: Date())
        ])

        print("Clinic created: \(clinicID)")

        // 3. Create the admin user profile
        try await db.collection("users").document(uid).setData([
            "email": email,
            "displayName": "\(firstName) \(lastName)",
            "role": "admin",
            "clinicID": clinicID,
            "phone": "",
            "isActive": true,
            "lastLogin": Timestamp(date: Date()),
            "dateCreated": Timestamp(date: Date())
        ])

        print("Admin profile created")

        // 4. Create default settings for the clinic
        try? await db.collection("settings").document("categories").setData([
            "list": [
                "Orthopedic", "Cervical", "Lumbar",
                "Wound Care", "Respiratory", "Diabetic Supplies",
                "Compression", "Mobility Aids",
                "Electrical Stimulation", "General Medical"
            ]
        ], merge: true)

        try? await db.collection("settings").document("sizes").setData([
            "list": [
                "XS", "S", "M", "L", "XL", "XXL",
                "Universal", "Pediatric", "Custom",
                "N/A", "RT", "LT"
            ]
        ], merge: true)

        // 5. Load the profile — this triggers isAuthenticated = true
        await loadUserProfile(uid: uid)

        print("Registration complete!")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Sign Out
    // ══════════════════════════════════════════════════════

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()  // Also sign out of Google
            currentUser = nil
            currentClinic = nil
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
        try await Auth.auth().sendPasswordReset(withEmail: email)
        print("Password reset email sent to \(email)")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Remember Me
    // ══════════════════════════════════════════════════════

    var savedEmail: String? {
        UserDefaults.standard.string(forKey: "savedEmail")
    }

    var hasRememberedEmail: Bool {
        savedEmail != nil
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Apple Sign-In Helpers
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
        // FIXED: Was missing 'W' in the uppercase letters.
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

        var errorDescription: String? {
            switch self {
            case .noRootViewController:
                return "Unable to find root view controller."
            case .missingToken:
                return "Authentication failed. Please try again."
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview Support
//
// Use AuthManager.preview() in #Preview blocks to get a manager
// that doesn't touch Firebase. Pass isAuthenticated/currentUser
// to preview different states.
// ══════════════════════════════════════════════════════

#if DEBUG
extension AuthManager {
    /// Creates an AuthManager safe for SwiftUI previews.
    /// Does not attach a Firebase auth listener.
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
