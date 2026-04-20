//
//  JoinClinicView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/16/26.
//


//
//  JoinClinicView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  For invited users who want to sign in with email/password
//  instead of Google/Apple.
//
//  Flow:
//  1. User enters email + password
//  2. Creates Firebase Auth account
//  3. Checks for invitation
//  4. If invited → creates profile → signed in
//  5. If not invited → shows error
//

import SwiftUI
import FirebaseFirestore
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

                // ── Or use social sign-in ──
                HStack {
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 1)
                    Text("or just use")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, AppSpacing.md)
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(height: 1)
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.xxl)

                HStack(spacing: AppSpacing.lg) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textPrimary)
                    Text("or")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textTertiary)
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppColors.textPrimary)
                    Text("from the login page")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.top, AppSpacing.md)

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
                let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

                // 1. Create Firebase Auth account FIRST
                let result = try await Auth.auth().createUser(
                    withEmail: normalizedEmail,
                    password: password
                )

                print("Account created: \(result.user.uid)")

                // 2. Now we're authenticated — check invitation
                let accepted = await UserManager.checkAndAcceptInvitation(
                    uid: result.user.uid,
                    email: normalizedEmail,
                    displayName: "User"
                )

                if accepted {
                    print("Invitation accepted!")
                    // Auth listener will pick up the profile and sign in
                    await MainActor.run {
                        dismiss()
                    }
                } else {
                    // No invitation — delete the account we just created
                    print("No invitation found — deleting account")
                    try? await result.user.delete()
                    try? Auth.auth().signOut()

                    await MainActor.run {
                        errorMessage = "No invitation found for this email. Ask your clinic admin to invite you first."
                        isJoining = false
                    }
                }

            } catch {
                await MainActor.run {
                    let nsError = error as NSError
                    if nsError.code == 17007 {
                        errorMessage = "An account with this email already exists. Try signing in from the login page."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isJoining = false
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Check Invitation
    // ══════════════════════════════════════════════════════

    private func checkInvitationExists(email: String) async -> Bool {
        do {
            let doc = try await Firestore.firestore()
                .collection("invitations")
                .document(email)
                .getDocument()

            guard let data = doc.data(),
                  data["status"] as? String == "pending"
            else {
                return false
            }

            return true
        } catch {
            print("Invitation check error: \(error)")
            return false
        }
    }
}

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
        .environmentObject(AuthManager())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    JoinClinicView()
        .environmentObject(AuthManager())
        .preferredColorScheme(.dark)
}
