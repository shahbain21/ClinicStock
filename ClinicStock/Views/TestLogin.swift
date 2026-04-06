//
//  TestLogin.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/6/26.
//

import SwiftUI

struct TestLoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Logo
            Image(systemName: "cross.case.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("ClinicStock")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            
            Text("Sign in to continue")
                .foregroundColor(.secondary)
            
            // Login fields
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    login()
                } label: {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(email.isEmpty || password.isEmpty || isLoading)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Test credentials hint
            VStack(spacing: 4) {
                Text("Test Login:")
                    .font(.caption.bold())
                Text("admin@clinicstock.com")
                    .font(.caption)
                Text("Test1234!")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.bottom, 20)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func login() {
        isLoading = true
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }
}
