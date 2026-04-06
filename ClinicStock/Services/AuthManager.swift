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

class AuthManager: ObservableObject {
    
    // These properties update the UI automatically
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var currentUser: AppUser?
    @Published var currentClinic: Clinic?
    @Published var errorMessage: String?
    
    // Reference to Firestore database
    private let db = Firestore.firestore()
    
    // Listener that watches for login/logout
    private var authListener: AuthStateDidChangeListenerHandle?
    
    // This runs when AuthManager is created
    init() {
        listenForAuthChanges()
    }
    
    // Clean up when AuthManager is destroyed
    deinit {
        if let listener = authListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    // ── Watch for login/logout changes ──
    private func listenForAuthChanges() {
        authListener = Auth.auth().addStateDidChangeListener {
            [weak self] _, firebaseUser in
            
            guard let self = self else { return }
            
            if let firebaseUser = firebaseUser {
                // Someone is logged in
                print(" User detected: \(firebaseUser.uid)")
                Task {
                    await self.loadUserProfile(uid: firebaseUser.uid)
                }
            } else {
                // Nobody is logged in
                print(" No user logged in")
                DispatchQueue.main.async {
                    self.currentUser = nil
                    self.currentClinic = nil
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
        }
    }
    
    // ── Sign In ──
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(
            withEmail: email,
            password: password
        )
        print("Signed in: \(result.user.uid)")
        
        // Update last login time
        try? await db.collection("users")
            .document(result.user.uid)
            .updateData(["lastLogin": Timestamp(date: Date())])
        
        await loadUserProfile(uid: result.user.uid)
    }
    
    // ── Load user's full profile after login ──
    private func loadUserProfile(uid: String) async {
        do {
            // 1. Get user document
            let userDoc = try await db.collection("users")
                .document(uid)
                .getDocument()
            
            guard let user = try? userDoc.data(as: AppUser.self) else {
                print(" Could not find user profile")
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isLoading = false
                    self.errorMessage = "User profile not found. Contact your admin."
                }
                return
            }
            
            // 2. Check if user is active
            guard user.isActive else {
                print(" User is deactivated")
                try? Auth.auth().signOut()
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isLoading = false
                    self.errorMessage = "Your account has been deactivated."
                }
                return
            }
                        
            // 3. Get their clinic
            let clinicDoc = try await db.collection("clinics")
                .document(user.clinicID)
                .getDocument()
            let clinic = try? clinicDoc.data(as: Clinic.self)
            
            // 4. Update the UI
            await MainActor.run {
                self.currentUser = user
                self.currentClinic = clinic
                self.isAuthenticated = true
                self.isLoading = false
                self.errorMessage = nil
                
                print(" Profile loaded:")
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
    
    // ── Sign Out ──
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            currentClinic = nil
            isAuthenticated = false
            print(" Signed out")
        } catch {
            print(" Error signing out: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    // ── Reset Password ──
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        print(" Password reset email sent to \(email)")
    }
}
