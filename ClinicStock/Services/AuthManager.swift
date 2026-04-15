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

    init() {
        listenForAuthChanges()
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
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController
        else {
            throw AuthError.noRootViewController
        }

        // Start Google Sign-In flow
        let result = try await GIDSignIn.sharedInstance.signIn(
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

        // Handle profile creation/update
        await handleSocialSignIn(
            uid: authResult.user.uid,
            email: authResult.user.email ?? "",
            displayName: result.user.profile?.name ?? "User"
        )
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

            // Build display name from Apple's response
            let displayName = buildDisplayName(
                from: appleIDCredential.fullName,
                fallback: authResult.user.displayName
            )

            // Handle profile creation/update
            await handleSocialSignIn(
                uid: authResult.user.uid,
                email: appleIDCredential.email ?? authResult.user.email ?? "",
                displayName: displayName
            )

        case .failure(let error):
            // User cancelled — don't show error
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                return
            }
            throw error
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Shared Social Sign-In Handler
    // Checks if user profile exists, creates one if not
    // ══════════════════════════════════════════════════════

    private func handleSocialSignIn(
        uid: String,
        email: String,
        displayName: String
    ) async {
        do {
            let userDoc = try await db.collection("users")
                .document(uid)
                .getDocument()

            if userDoc.exists {
                // Existing user — update last login
                try? await db.collection("users")
                    .document(uid)
                    .updateData(["lastLogin": Timestamp(date: Date())])

                await loadUserProfile(uid: uid)
            } else {
                // New social sign-in — no clinic yet
                // They need to be added by an admin OR go through registration
                await MainActor.run {
                    self.isLoading = false
                    self.isAuthenticated = false
                    self.errorMessage = "No account found. Ask your clinic admin to add you, or set up a new clinic."
                }

                // Sign out since they don't have a profile yet
                try? Auth.auth().signOut()
            }
        } catch {
            print("Social sign-in profile check error: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Load User Profile
    // ══════════════════════════════════════════════════════

    private func loadUserProfile(uid: String) async {
        do {
            let userDoc = try await db.collection("users")
                .document(uid)
                .getDocument()

            guard let user = try? userDoc.data(as: AppUser.self) else {
                print("Could not find user profile")
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isLoading = false
                    self.errorMessage = "User profile not found. Contact your admin."
                }
                return
            }

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

        } catch {
            print("Error loading profile: \(error)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // Add this method to AuthManager.swift

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
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
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
