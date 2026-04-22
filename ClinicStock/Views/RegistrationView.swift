//
//  RegistrationView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/21/26.
//


//
//  RegistrationView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  First-time clinic setup. Collects admin + clinic details and calls
//  AuthManager.registerClinic, which writes:
//    - A Firebase Auth account for the admin
//    - A clinic document
//    - A user profile with role "admin"
//    - Default settings if the settings docs don't already exist
//
//  On success the auth listener flips isAuthenticated and RootView swaps
//  in MainTabView. The sheet dismisses automatically.
//
//  On failure the Auth account is rolled back (by AuthManager.registerClinic)
//  so the admin can retry with the same email.
//

import SwiftUI

struct RegistrationView: View {

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    // Admin identity
    @State private var firstName = ""
    @State private var lastName = ""

    // Clinic identity
    @State private var organizationName = ""
    @State private var location = ""

    // Credentials
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var isRegistering = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Drag Indicator ──
                Capsule()
                    .fill(AppColors.border)
                    .frame(width: 40, height: 5)
                    .padding(.top, AppSpacing.md)

                Spacer().frame(height: 40)

                // ── Header ──
                VStack(spacing: AppSpacing.sm) {
                    Text("Set Up Your Clinic")
                        .font(AppFonts.title)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Create an admin account and register your clinic")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, AppSpacing.xxl)

                // ── Info Banner ──
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppColors.accent)
                    Text("You'll be the first admin for this clinic. You can invite staff from Settings after signing in.")
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(AppSpacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColors.accentLight)
                )
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.xxl)

                // ── Admin Section ──
                sectionHeader("About you")

                VStack(spacing: AppSpacing.xl) {
                    UnderlineTextField(
                        title: "First Name",
                        placeholder: "Your first name",
                        text: $firstName
                    )

                    UnderlineTextField(
                        title: "Last Name",
                        placeholder: "Your last name",
                        text: $lastName
                    )
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.xl)

                // ── Clinic Section ──
                sectionHeader("About your clinic")

                VStack(spacing: AppSpacing.xl) {
                    UnderlineTextField(
                        title: "Clinic Name",
                        placeholder: "e.g. Specialty Medical Center",
                        text: $organizationName
                    )

                    UnderlineTextField(
                        title: "Location",
                        placeholder: "City or street address",
                        text: $location
                    )
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.xl)

                // ── Credentials Section ──
                sectionHeader("Admin login")

                VStack(spacing: AppSpacing.xl) {
                    UnderlineTextField(
                        title: "Email",
                        placeholder: "admin@yourclinic.com",
                        text: $email,
                        keyboardType: .emailAddress
                    )

                    UnderlineTextField(
                        title: "Password",
                        placeholder: "Create a password",
                        text: $password,
                        isSecure: true
                    )

                    UnderlineTextField(
                        title: "Confirm Password",
                        placeholder: "Confirm your password",
                        text: $confirmPassword,
                        isSecure: true
                    )
                }
                .padding(.horizontal, AppSpacing.xxl)

                // ── Password Requirements ──
                if !password.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        PasswordRequirement(
                            text: "At least 8 characters",
                            isMet: password.count >= 8
                        )
                        PasswordRequirement(
                            text: "Contains a number",
                            isMet: password.rangeOfCharacter(from: .decimalDigits) != nil
                        )
                        PasswordRequirement(
                            text: "Contains an uppercase letter",
                            isMet: password.rangeOfCharacter(from: .uppercaseLetters) != nil
                        )
                        PasswordRequirement(
                            text: "Passwords match",
                            isMet: !confirmPassword.isEmpty && password == confirmPassword
                        )
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.lg)
                }

                // ── Error ──
                if let error = errorMessage {
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

                // ── Create Button ──
                Button(action: register) {
                    if isRegistering {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                    } else {
                        Text("Create Clinic")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
                .disabled(!isFormValid || isRegistering)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.xxxl)

                // ── Back Link ──
                Button(action: { dismiss() }) {
                    Text("Back To Login Page")
                        .font(AppFonts.captionSemibold)
                        .foregroundColor(AppColors.accent)
                        .underline()
                }
                .padding(.top, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.xxxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .onAppear {
            authManager.clearError()
            errorMessage = nil
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Section Header Helper
    // ══════════════════════════════════════════════════════

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(AppFonts.captionSemibold)
                .foregroundColor(AppColors.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxl)
        .padding(.bottom, AppSpacing.md)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Validation
    // ══════════════════════════════════════════════════════

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !organizationName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !location.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        isPasswordValid &&
        password == confirmPassword
    }

    private var isPasswordValid: Bool {
        password.count >= 8 &&
        password.rangeOfCharacter(from: .decimalDigits) != nil &&
        password.rangeOfCharacter(from: .uppercaseLetters) != nil
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Register Action
    // ══════════════════════════════════════════════════════

    private func register() {
        isRegistering = true
        errorMessage = nil

        Task {
            do {
                try await authManager.registerClinic(
                    firstName: firstName,
                    lastName: lastName,
                    organizationName: organizationName,
                    location: location,
                    email: email,
                    password: password
                )
                // Auth listener will flip isAuthenticated and RootView
                // will swap to MainTabView. Sheet dismisses on the way out.
                dismiss()
            } catch {
                let nsError = error as NSError
                if nsError.code == 17007 {
                    errorMessage = "An account with this email already exists. Try signing in instead."
                } else {
                    errorMessage = error.localizedDescription
                }
                isRegistering = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    RegistrationView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RegistrationView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.dark)
}