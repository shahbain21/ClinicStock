//
//  JoinClinicView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/16/26.
//
//  For invited users who want to sign in with email/password instead of
//  Google/Apple.
//
//  FIXES:
//  - Auth logic moved into AuthManager.joinClinic(email:password:). The
//    view just calls the manager and reacts to success/failure.
//  - Dead helper checkInvitationExists() removed.
//  - Apple/Google visual reminder simplified to a single line of text.
//  - errorMessage cleared on appear so stale errors from a previous
//    sheet don't bleed in.
//  - Preview uses AuthManager.preview().
//

import SwiftUI
import FirebaseAuth

struct JoinClinicView: View {

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Drag Indicator ──
                Capsule()
                    .fill(AppColors.border)
                    .frame(width: 40, height: 5)
                    .padding(.top, AppSpacing.md)

                Spacer().frame(height: 60)

                // ── Header ──
                VStack(spacing: AppSpacing.sm) {
                    Text("Join Your Clinic")
                        .font(AppFonts.title)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Create your account to join an existing clinic")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, AppSpacing.xxxl)

                // ── Info Banner ──
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Your clinic admin must have invited you first. Use the same email address they invited you with.")
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

                // ── Form Fields ──
                VStack(spacing: AppSpacing.xl) {

                    UnderlineTextField(
                        title: "Email",
                        placeholder: "Enter the email you were invited with",
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

                // ── Join Button ──
                Button(action: joinClinic) {
                    if isJoining {
                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                    } else {
                        Text("Join Clinic")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
                .disabled(!isFormValid || isJoining)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.xxxl)

                // ── Social sign-in reminder ──
                Text("You can also sign in with Apple or Google from the login page.")
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.xl)

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
    // MARK: - Validation
    // ══════════════════════════════════════════════════════

    private var isFormValid: Bool {
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
    // MARK: - Join Action
    // ══════════════════════════════════════════════════════

    private func joinClinic() {
        isJoining = true
        errorMessage = nil

        Task {
            do {
                try await authManager.joinClinic(email: email, password: password)
                // Auth listener will flip isAuthenticated. Sheet dismisses
                // itself because RootView will swap LoginView → MainTabView.
                dismiss()
            } catch {
                let nsError = error as NSError

                // Print the full error so we can see what Firebase
                // actually returned. The numeric code alone is rarely
                // enough — the userInfo and message clarify the case.
                print("[Join] error code=\(nsError.code) domain=\(nsError.domain)")
                print("[Join] localizedDescription: \(nsError.localizedDescription)")
                print("[Join] userInfo: \(nsError.userInfo)")

                switch nsError.code {
                case AuthErrorCode.emailAlreadyInUse.rawValue:
                    errorMessage = "An account with this email already exists. Try the login page, or use Forgot Password to set a new password."
                case AuthErrorCode.weakPassword.rawValue:
                    errorMessage = "Password is too weak. Try a longer password with letters and numbers."
                case AuthErrorCode.invalidEmail.rawValue:
                    errorMessage = "That email doesn't look right. Double-check the spelling."
                case AuthErrorCode.networkError.rawValue:
                    errorMessage = "Network error. Check your connection and try again."
                default:
                    // Show the system-localized message — usually clearer
                    // than a custom string when we don't recognize the code.
                    errorMessage = error.localizedDescription
                }
                isJoining = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Password Requirement Row
// ══════════════════════════════════════════════════════

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isMet ? AppColors.success : AppColors.textTertiary)

            Text(text)
                .font(AppFonts.caption)
                .foregroundColor(isMet ? AppColors.textPrimary : AppColors.textTertiary)
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    JoinClinicView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    JoinClinicView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.dark)
}
