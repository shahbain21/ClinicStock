//
//  ForgotPasswordView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  UPDATED:
//  - Dark mode support
//  - Keyboard dismiss
//  - Consistent color tokens
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

            Spacer()
                .frame(height: 80)

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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                    .foregroundColor(AppColors.accent)
                    .underline()
            }
            .padding(.bottom, AppSpacing.xxxl)
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .animation(.easeInOut(duration: 0.3), value: errorMessage)
        .appBackground()
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

#Preview("Light") {
    ForgotPasswordView()
        .environmentObject(AuthManager())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ForgotPasswordView()
        .environmentObject(AuthManager())
        .preferredColorScheme(.dark)
}
// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    ForgotPasswordView()
        .environmentObject(AuthManager())
}
