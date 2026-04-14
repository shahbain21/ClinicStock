//
//  ForgotPasswordView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/13/26.
//

//
//  ForgotPasswordView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//

import SwiftUI

struct ForgotPasswordView: View {

    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {

            Spacer()
                .frame(height: 100)

            // ── Header ──
            VStack(spacing: AppSpacing.md) {
                Text("Forgot Password")
                    .font(AppFonts.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("Enter Email To Send A Reset Link")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.bottom, AppSpacing.xxxl)

            // ── Email Field ──
            UnderlineTextField(
                title: "Email",
                placeholder: "Enter your email",
                text: $email,
                keyboardType: .emailAddress
            )
            .padding(.horizontal, AppSpacing.xxl)

            // ── Error Message ──
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

            // ── Success Message ──
            if showSuccess {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Reset link sent! Check your inbox.")
                        .font(AppFonts.caption)
                }
                .foregroundColor(AppColors.success)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.lg)
            }

            // ── Send Reset Button ──
            Button(action: sendReset) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(tint: .white)
                        )
                } else {
                    Text("Send Reset Login")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
            .disabled(!isFormValid || isSending)
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.top, AppSpacing.xxxl)

            Spacer()

            // ── Back Link ──
            Button(action: { dismiss() }) {
                Text("Back To Login Page")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.primary)
                    .underline()
            }
            .padding(.bottom, AppSpacing.xxxl)
        }
        .appBackground()
    }

    // ── Validation ──
    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    // ── Send Reset Action ──
    private func sendReset() {
        isSending = true
        errorMessage = nil
        showSuccess = false

        Task {
            do {
                try await authManager.resetPassword(
                    email: email.trimmingCharacters(in: .whitespaces)
                )

                await MainActor.run {
                    showSuccess = true
                    isSending = false
                }

                // Auto dismiss after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSending = false
                }
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthManager())
}
