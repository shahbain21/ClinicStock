//
//  UserManagementView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/16/26.
//

//  Admin view: see all clinic users, change roles, deactivate.
//

import SwiftUI

struct UserManagementView: View {

    @EnvironmentObject var authManager: AuthManager
    @StateObject private var userManager = UserManager()

    @State private var showAddUser = false
    @State private var selectedUser: AppUser? = nil
    @State private var showEditRole = false
    @State private var showDeactivateConfirm = false
    @State private var newRole: AppUser.UserRole = .staff

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──
            HStack {
                Text("User Management")
                    .font(AppFonts.title2)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button(action: { showAddUser = true }) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add User")
                            .font(AppFonts.captionSemibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        Capsule().fill(AppColors.accent)
                    )
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)

            // ── User Count ──
            HStack {
                Text("\(userManager.clinicUsers.count) users")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.md)

            // ── Loading ──
            if userManager.isLoading {
                Spacer()
                ProgressView("Loading users...")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()

            // ── Empty ──
            } else if userManager.clinicUsers.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "person.2",
                    title: "No Users",
                    message: "Add team members to your clinic",
                    buttonTitle: "Add User",
                    onAction: { showAddUser = true }
                )
                Spacer()

            // ── User List ──
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(userManager.clinicUsers) { user in
                            // Add inside the ScrollView, after the ForEach(userManager.clinicUsers):

                            // ── Pending Invitations ──
                            if !userManager.pendingInvitations.isEmpty {
                                VStack(alignment: .leading, spacing: AppSpacing.md) {
                                    Text("Pending Invitations")
                                        .font(AppFonts.title3)
                                        .foregroundColor(AppColors.textPrimary)
                                        .padding(.top, AppSpacing.xl)

                                    ForEach(userManager.pendingInvitations) { invite in
                                        HStack(spacing: AppSpacing.lg) {
                                            // Pending icon
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(AppColors.warning)
                                                .frame(width: 44, height: 44)
                                                .background(
                                                    Circle().fill(AppColors.warningLight)
                                                )

                                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                                Text(invite.displayName)
                                                    .font(AppFonts.bodySemibold)
                                                    .foregroundColor(AppColors.textPrimary)
                                                Text(invite.email)
                                                    .font(AppFonts.caption)
                                                    .foregroundColor(AppColors.textSecondary)
                                                RoleBadge(role: invite.roleEnum)
                                            }

                                            Spacer()

                                            // Cancel invitation
                                            Button(action: {
                                                cancelInvitation(email: invite.email)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 22))
                                                    .foregroundColor(AppColors.danger)
                                            }
                                        }
                                        .padding(AppSpacing.lg)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppRadius.medium)
                                                .fill(AppColors.cardBackground)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: AppRadius.medium)
                                                        .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                        .cardShadow()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
        }
        .appBackground()
        .onAppear {
            loadUsers()
        }
        // ── Add User Sheet ──
        .sheet(isPresented: $showAddUser) {
            AddUserView(userManager: userManager)
                .environmentObject(authManager)
                .onDisappear {
                    loadUsers()
                }
        }
        // ── Edit Role Alert ──
        .alert("Change Role", isPresented: $showEditRole) {
            ForEach(AppUser.UserRole.allCases, id: \.self) { role in
                Button(role == .admin ? "Admin (Full Access)" : role.displayName) {
                    changeRole(to: role)
                }
            }
            Button("Cancel", role: .cancel) {
                selectedUser = nil
            }
        } message: {
            if let user = selectedUser {
                Text("Change \(user.displayName)'s role from \(user.role.displayName) to:")
            }
        }
        // ── Deactivate Confirmation ──
        .alert("Deactivate User?", isPresented: $showDeactivateConfirm) {
            Button("Deactivate", role: .destructive) {
                deactivateUser()
            }
            Button("Cancel", role: .cancel) {
                selectedUser = nil
            }
        } message: {
            if let user = selectedUser {
                Text("\(user.displayName) will no longer be able to sign in. You can reactivate them later.")
            }
        }
        // ── Error ──
        .alert("Error", isPresented: .init(
            get: { userManager.errorMessage != nil },
            set: { if !$0 { userManager.errorMessage = nil } }
        )) {
            Button("OK") { userManager.errorMessage = nil }
        } message: {
            Text(userManager.errorMessage ?? "")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func loadUsers() {
        guard let clinicID = authManager.currentUser?.clinicID else { return }
        Task {
            await userManager.loadUsers(clinicID: clinicID)
        }
    }

    private func changeRole(to role: AppUser.UserRole) {
        guard let user = selectedUser,
              let admin = authManager.currentUser,
              let userID = user.id
        else { return }

        Task {
            try? await userManager.updateUserRole(
                userID: userID,
                newRole: role,
                clinicID: admin.clinicID,
                by: admin
            )
            selectedUser = nil
        }
    }
    
    private func cancelInvitation(email: String) {
        guard let admin = authManager.currentUser else { return }

        Task {
            try? await userManager.cancelInvitation(
                email: email,
                clinicID: admin.clinicID,
                by: admin
            )
        }
    }

    private func deactivateUser() {
        guard let user = selectedUser,
              let admin = authManager.currentUser,
              let userID = user.id
        else { return }

        Task {
            try? await userManager.deactivateUser(
                userID: userID,
                clinicID: admin.clinicID,
                by: admin
            )
            selectedUser = nil
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - User Row
// ══════════════════════════════════════════════════════

struct UserRow: View {

    let user: AppUser
    let isCurrentUser: Bool
    var onEditRole: () -> Void
    var onDeactivate: () -> Void

    @State private var showActions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.lg) {

                // Avatar
                UserAvatar(
                    name: user.displayName,
                    role: user.role,
                    size: 44
                )

                // Info
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(user.displayName)
                            .font(AppFonts.bodySemibold)
                            .foregroundColor(AppColors.textPrimary)

                        if isCurrentUser {
                            Text("(You)")
                                .font(AppFonts.footnote)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Text(user.email)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)

                    RoleBadge(role: user.role)
                }

                Spacer()

                // Actions menu
                if !isCurrentUser {
                    Menu {
                        Button(action: onEditRole) {
                            Label("Change Role", systemImage: "person.badge.key")
                        }

                        Divider()

                        Button(role: .destructive, action: onDeactivate) {
                            Label("Deactivate", systemImage: "person.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(AppColors.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    NavigationStack {
        UserManagementView()
            .environmentObject(AuthManager())
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        UserManagementView()
            .environmentObject(AuthManager())
    }
    .preferredColorScheme(.dark)
}
