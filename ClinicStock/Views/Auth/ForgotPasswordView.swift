//
//  ForgotPasswordView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  FIXES:
//  - "Send Reset Login" typo fixed to "Send Reset Link".
//  - Duplicate #Preview blocks removed (was three previews, two named
//    Light/Dark and one unnamed copy).
//  - errorMessage cleared on appear.
//  - Preview uses AuthManager.preview().
//  - Form hidden after success to reduce visual clutter during the
//    auto-dismiss delay.
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

            // ── Drag Indicator ──
            Capsule()
                .fill(AppColors.border)
                .frame(width: 40, height: 5)
                .padding(.top, AppSpacing.md)

            Spacer().frame(height: 80)

            // ── Header ──
            VStack(spacing: AppSpacing.md) {
                Text("Forgot Password")
                    .font(AppFonts.title)
                    .foregroundColor(AppColors.textPrimary)

                Text("Enter your email to send a reset link")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.bottom, AppSpacing.xxxl)

            if showSuccess {
                successState
            } else {
                requestForm
            }

            Spacer()

            // ── Back Link ──
            Button(action: { dismiss() }) {
                Text("Back To Login Page")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.accent)
                    .underline()
            }
            .padding(.bottom, AppSpacing.xxxl)
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
        .appBackground()
        .onAppear {
            authManager.clearError()
            errorMessage = nil
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - States
    // ══════════════════════════════════════════════════════

    private var requestForm: some View {
        VStack(spacing: 0) {
            UnderlineTextField(
                title: "Email",
                placeholder: "Enter your email",
                text: $email,
                keyboardType: .emailAddress
            )
            .padding(.horizontal, AppSpacing.xxl)

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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: sendReset) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(
                            CircularProgressViewStyle(tint: .white)
                        )
                } else {
                    Text("Send Reset Link")
                }
            }
            .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
            .disabled(!isFormValid || isSending)
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.top, AppSpacing.xxxl)
        }
    }

    private var successState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.success)

            Text("Reset link sent!")
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)

            Text("Check your inbox for instructions to reset your password.")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
        }
        .padding(.horizontal, AppSpacing.xxl)
        .transition(.opacity)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Validation
    // ══════════════════════════════════════════════════════

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Send Reset Action
    // ══════════════════════════════════════════════════════

    private func sendReset() {
        isSending = true
        errorMessage = nil

        Task {
            do {
                try await authManager.resetPassword(email: email)

                showSuccess = true
                isSending = false

                // Auto-dismiss after 2 seconds so the user can see the
                // confirmation without feeling stuck on the sheet.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    ForgotPasswordView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ForgotPasswordView()
        .environmentObject(AuthManager.preview())
        .preferredColorScheme(.dark)
}
