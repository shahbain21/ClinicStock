//
//  LoginView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/14/26.
//
//  UPDATED:
//  - Dark mode support
//  - Apple button adapts to color scheme
//  - Google button adapts to color scheme
//  - Registration sheet wired
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var showForgotPassword = false
    @State private var showRegistration = false
    @State private var isSigningIn = false
    @State private var isSocialSigningIn = false
    @State private var showJoinClinic = false


    var body: some View {
        NavigationStack {
            ScrollView {
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
                        UnderlineTextField(
                            title: "Email",
                            placeholder: "Enter your email",
                            text: $email,
                            keyboardType: .emailAddress
                        )

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
                                        rememberMe ? AppColors.accent : AppColors.textTertiary
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
                                .foregroundColor(AppColors.accent)
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

                    // ── Divider ──
                    HStack {
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(height: 1)
                        Text("or")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.horizontal, AppSpacing.md)
                        Rectangle()
                            .fill(AppColors.border)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.xxl)

                    // ── Social Sign-In Buttons ──
                    VStack(spacing: AppSpacing.md) {

                        // Apple Sign-In — adapts style to color scheme
                        SignInWithAppleButton(.signIn) { request in
                            let appleRequest = authManager.createAppleSignInRequest()
                            request.requestedScopes = appleRequest.requestedScopes
                            request.nonce = appleRequest.nonce
                        } onCompletion: { result in
                            handleAppleSignIn(result: result)
                        }
                        .signInWithAppleButtonStyle(
                            colorScheme == .dark ? .white : .black
                        )
                        .frame(height: 50)
                        .cornerRadius(AppRadius.medium)

                        // Google Sign-In — adapts to color scheme
                        Button(action: signInWithGoogle) {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(
                                        colorScheme == .dark
                                            ? .white
                                            : .red
                                    )

                                Text("Sign in with Google")
                                    .font(AppFonts.bodySemibold)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .fill(AppColors.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium)
                                    .stroke(AppColors.border, lineWidth: 1.5)
                            )
                        }
                        .disabled(isSocialSigningIn)
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.xl)

                    // ── Loading indicator for social sign-in ──
                    if isSocialSigningIn {
                        HStack(spacing: AppSpacing.sm) {
                            ProgressView()
                                .progressViewStyle(
                                    CircularProgressViewStyle(tint: AppColors.accent)
                                )
                            Text("Signing in...")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.top, AppSpacing.lg)
                    }

                    Spacer()
                        .frame(height: AppSpacing.huge)

                    // ── Bottom Links ──
                    VStack(spacing: AppSpacing.md) {
                        VStack(spacing: AppSpacing.xs) {
                            Text("First time using the app?")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)

                            Button(action: { showRegistration = true }) {
                                Text("Set up your clinic")
                                    .font(AppFonts.captionSemibold)
                                    .foregroundColor(AppColors.accent)
                                    .underline()
                            }
                        }

                        VStack(spacing: AppSpacing.xs) {
                            Text("Been invited to a clinic?")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)

                            Button(action: { showJoinClinic = true }) {
                                Text("Join with email")
                                    .font(AppFonts.captionSemibold)
                                    .foregroundColor(AppColors.accent)
                                    .underline()
                            }
                        }
                    }
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationBarHidden(true)
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
                    .environmentObject(authManager)
            }
//            .sheet(isPresented: $showRegistration) {
//                //RegistrationView()
//                    //.environmentObject(authManager)
//            }
            .sheet(isPresented: $showJoinClinic) {
                JoinClinicView()
                    .environmentObject(authManager)
            }
            .onAppear {
                loadSavedEmail()
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
    }

    private func loadSavedEmail() {
        if let saved = authManager.savedEmail {
            email = saved
            rememberMe = true
        }
    }

    private func signIn() {
        isSigningIn = true
        authManager.errorMessage = nil

        Task {
            do {
                try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespaces),
                    password: password
                )

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

    private func signInWithGoogle() {
        isSocialSigningIn = true
        authManager.errorMessage = nil

        Task {
            do {
                try await authManager.signInWithGoogle()
            } catch {
                await MainActor.run {
                    authManager.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isSocialSigningIn = false
            }
        }
    }

    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        isSocialSigningIn = true
        authManager.errorMessage = nil

        Task {
            do {
                try await authManager.handleAppleSignIn(result: result)
            } catch {
                await MainActor.run {
                    authManager.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isSocialSigningIn = false
            }
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
