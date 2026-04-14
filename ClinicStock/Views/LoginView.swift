//
//  LoginView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/13/26.
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var showForgotPassword = false
    @State private var showRegistration = false
    @State private var isSigningIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                Spacer()
                    .frame(height: 80)

                // ── Header ──
                VStack(spacing: AppSpacing.sm) {
                    Text("Welcome Back")
                        .font(AppFonts.title)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Sign in to your account")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.bottom, AppSpacing.xxxl)

                // ── Form Fields ──
                VStack(spacing: AppSpacing.xxl) {

                    // Email
                    UnderlineTextField(
                        title: "Email",
                        placeholder: "Enter your email",
                        text: $email,
                        keyboardType: .emailAddress
                    )

                    // Password
                    UnderlineTextField(
                        title: "Password",
                        placeholder: "Enter your password",
                        text: $password,
                        isSecure: true
                    )
                }
                .padding(.horizontal, AppSpacing.xxl)

                // ── Remember Me / Forgot Password ──
                HStack {
                    Button(action: { rememberMe.toggle() }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                .font(.system(size: 18))
                                .foregroundColor(
                                    rememberMe ? AppColors.primary : AppColors.textTertiary
                                )
                            Text("Remember me")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: { showForgotPassword = true }) {
                        Text("Forgot Password?")
                            .font(AppFonts.captionSemibold)
                            .foregroundColor(AppColors.primary)
                    }
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.lg)

                // ── Error Message ──
                if let error = authManager.errorMessage {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14))
                        Text(error)
                            .font(AppFonts.caption)
                    }
                    .foregroundColor(AppColors.danger)
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.lg)
                }

                // ── Sign In Button ──
                Button(action: signIn) {
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
                .disabled(!isFormValid || isSigningIn)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.xxxl)

                Spacer()

                // ── Bottom Link ──
                VStack(spacing: AppSpacing.xs) {
                    Text("First time using the app?")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Button(action: { showRegistration = true }) {
                        Text("Set up your clinic")
                            .font(AppFonts.captionSemibold)
                            .foregroundColor(AppColors.primary)
                            .underline()
                    }
                }
                .padding(.bottom, AppSpacing.xxxl)
            }
            .appBackground()
            .navigationBarHidden(true)
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .sheet(isPresented: $showRegistration) {
                // RegistrationView() — will build later
                Text("Registration")
            }
        }
    }

    // ── Validation ──
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
    }

    // ── Sign In Action ──
    private func signIn() {
        isSigningIn = true
        authManager.errorMessage = nil

        Task {
            do {
                try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )

                // Save email if remember me is on
                if rememberMe {
                    UserDefaults.standard.set(email, forKey: "savedEmail")
                } else {
                    UserDefaults.standard.removeObject(forKey: "savedEmail")
                }
            } catch {
                await MainActor.run {
                    authManager.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isSigningIn = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Underline Text Field
// Matches the prototype's minimal underline input style
// ══════════════════════════════════════════════════════

struct UnderlineTextField: View {
    let title: String
    var placeholder: String = ""
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default

    @State private var isPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)

            HStack {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .font(AppFonts.body)
                } else {
                    TextField(placeholder, text: $text)
                        .font(AppFonts.body)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                if isSecure {
                    Button(action: { isPasswordVisible.toggle() }) {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 16))
                    }
                }
            }

            Divider()
                .background(AppColors.border)
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
