//
//  AddUserView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Creates an invitation instead of an Auth account. Admin stays
//  signed in. No password reset needed.
//
//  FIXES:
//  - userManager is now an @EnvironmentObject instead of a passed-in
//    @ObservedObject. Matches the app-wide pattern.
//  - Redundant view-side trimming removed — UserManager.inviteUser
//    already normalizes inputs.
//  - Cancel button uses plain style instead of DangerButtonStyle;
//    cancelling an invitation form isn't a destructive action.
//  - errorMessage cleared on both appear and disappear to keep shared
//    state clean for other consumers.
//  - Preview uses AuthManager.preview() and shared environment.
//

import SwiftUI

struct AddUserView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var selectedRole: AppUser.UserRole = .staff
    @State private var isAdding = false
    @State private var showRolePicker = false
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    Spacer().frame(height: AppSpacing.xxl)

                    Text("Add User")
                        .font(AppFonts.title)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.bottom, AppSpacing.xxxl)

                    // ── Form ──
                    VStack(spacing: AppSpacing.xl) {

                        AppTextField(
                            title: "First Name",
                            text: $firstName,
                            placeholder: "Enter first name"
                        )

                        AppTextField(
                            title: "Last Name",
                            text: $lastName,
                            placeholder: "Enter last name"
                        )

                        AppTextField(
                            title: "Email",
                            text: $email,
                            placeholder: "Enter email",
                            keyboardType: .emailAddress
                        )

                        rolePicker
                    }
                    .padding(.horizontal, AppSpacing.xxl)

                    // ── Info Banner ──
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.accent)
                        Text("The user will be able to sign in with Google, Apple, or email/password using this email address. No password setup needed for Google/Apple.")
                            .font(AppFonts.footnote)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(AppSpacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.medium)
                            .fill(AppColors.accentLight)
                    )
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.xxl)

                    // ── Error ──
                    if let error = userManager.errorMessage {
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

                    Spacer().frame(height: AppSpacing.xxxl)

                    // ── Buttons ──
                    VStack(spacing: AppSpacing.lg) {
                        Button(action: inviteUser) {
                            if isAdding {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(tint: .white)
                                    )
                            } else {
                                Text("Send Invitation")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: !isFormValid))
                        .disabled(!isFormValid || isAdding)

                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(AppFonts.bodySemibold)
                                .foregroundColor(AppColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(AppColors.textPrimary)
                    }
                }
            }
            .alert("User Invited!", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text(userManager.successMessage ?? "\(firstName) can now sign in with \(email).")
            }
            .onAppear {
                userManager.errorMessage = nil
                userManager.successMessage = nil
            }
            .onDisappear {
                // Clear shared state so other views don't inherit stale
                // messages from this admin flow.
                userManager.errorMessage = nil
                userManager.successMessage = nil
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Role Picker
    // ══════════════════════════════════════════════════════

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Role")
                .font(AppFonts.captionMedium)
                .foregroundColor(AppColors.textSecondary)

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    showRolePicker.toggle()
                }
            }) {
                HStack {
                    RoleBadge(role: selectedRole)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                        .rotationEffect(.degrees(showRolePicker ? 180 : 0))
                }
                .padding(.horizontal, AppSpacing.lg)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColors.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(AppColors.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showRolePicker {
                VStack(spacing: 0) {
                    ForEach(availableRoles, id: \.self) { role in
                        Button(action: {
                            selectedRole = role
                            withAnimation { showRolePicker = false }
                        }) {
                            HStack {
                                RoleBadge(role: role)
                                Spacer()
                                Text(roleDescription(role))
                                    .font(AppFonts.footnote)
                                    .foregroundColor(AppColors.textTertiary)
                                if role == selectedRole {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)

                        if role != availableRoles.last {
                            Divider().padding(.horizontal, AppSpacing.lg)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColors.cardBackground)
                )
                .cardShadow()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Validation / Role Helpers
    // ══════════════════════════════════════════════════════

    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    private var availableRoles: [AppUser.UserRole] {
        [.staff, .editor, .manager, .admin]
    }

    private func roleDescription(_ role: AppUser.UserRole) -> String {
        switch role {
        case .staff: return "Check out only"
        case .editor: return "Add/edit stock"
        case .manager: return "Reports + alerts"
        case .admin: return "Full access"
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Invite Action
    // ══════════════════════════════════════════════════════

    private func inviteUser() {
        guard let currentUser = authManager.currentUser,
              let clinicID = authManager.effectiveClinicID else { return }

        isAdding = true
        userManager.errorMessage = nil

        Task {
            do {
                try await userManager.inviteUser(
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    role: selectedRole,
                    clinicID: clinicID,
                    by: currentUser
                )
                showSuccess = true
                isAdding = false
            } catch {
                userManager.errorMessage = error.localizedDescription
                isAdding = false
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    AddUserView()
        .environmentObject(AuthManager.preview())
        .environmentObject(UserManager())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AddUserView()
        .environmentObject(AuthManager.preview())
        .environmentObject(UserManager())
        .preferredColorScheme(.dark)
}
