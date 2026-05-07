//
//  UserManagementView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/16/26.
//
//  Admin view: see all clinic users, change roles, deactivate/reactivate.
//
//  CRITICAL FIX: The previous version had the pending-invitations block
//  nested inside ForEach(clinicUsers), which meant it rendered once per
//  user AND the actual UserRow was never instantiated. Users didn't show
//  up at all. Now the layout is: active users → deactivated users (if
//  toggled on) → pending invitations section.
//
//  OTHER FIXES:
//  - UserManager pulled from environment instead of a local @StateObject.
//    Shares state with the rest of the app.
//  - Deactivated users visible via a toggle, with a "Reactivate" action.
//    Previously they were hidden entirely with no recovery path.
//  - Role-change alert filters out the user's current role.
//  - Invitation cancel confirmed via alert.
//  - Deactivated user fetch goes through DatabaseService.
//  - Previews use AuthManager.preview().
//

import SwiftUI

struct UserManagementView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var userManager: UserManager

    @State private var showAddUser = false
    @State private var selectedUser: AppUser? = nil
    @State private var invitationToCancel: Invitation? = nil
    @State private var showEditRole = false
    @State private var showDeactivateConfirm = false
    @State private var showReactivateConfirm = false
    @State private var showCancelInvitationConfirm = false
    @State private var showDeactivatedUsers = false
    @State private var deactivatedUsers: [AppUser] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            summaryBar

            if userManager.isLoading {
                Spacer()
                ProgressView("Loading users...")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()

            } else if userManager.clinicUsers.isEmpty && userManager.pendingInvitations.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "person.2",
                    title: "No Users",
                    message: "Add team members to your clinic",
                    buttonTitle: "Add User",
                    onAction: { showAddUser = true }
                )
                Spacer()

            } else {
                userList
            }
        }
        .appBackground()
        .onAppear {
            loadUsers()
        }
        .sheet(isPresented: $showAddUser) {
            AddUserView()
                .environmentObject(authManager)
                .environmentObject(userManager)
                .onDisappear {
                    loadUsers()
                }
        }
        .alert("Change Role", isPresented: $showEditRole) {
            if let user = selectedUser {
                ForEach(availableRoles(excluding: user.role), id: \.self) { role in
                    Button(role == .admin ? "Admin (Full Access)" : role.displayName) {
                        changeRole(to: role)
                    }
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
        .alert("Reactivate User?", isPresented: $showReactivateConfirm) {
            Button("Reactivate") {
                reactivateUser()
            }
            Button("Cancel", role: .cancel) {
                selectedUser = nil
            }
        } message: {
            if let user = selectedUser {
                Text("\(user.displayName) will be able to sign in again.")
            }
        }
        .alert("Cancel Invitation?", isPresented: $showCancelInvitationConfirm) {
            Button("Cancel Invitation", role: .destructive) {
                if let invite = invitationToCancel {
                    performCancelInvitation(email: invite.email)
                }
                invitationToCancel = nil
            }
            Button("Keep", role: .cancel) {
                invitationToCancel = nil
            }
        } message: {
            if let invite = invitationToCancel {
                Text("\(invite.displayName) won't be able to join the clinic using this invitation. You can re-invite them later.")
            }
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { userManager.errorMessage = nil }
        } message: {
            Text(userManager.errorMessage ?? "")
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Subviews
    // ══════════════════════════════════════════════════════

    private var header: some View {
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
                .background(Capsule().fill(AppColors.accent))
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
    }

    private var summaryBar: some View {
        HStack {
            Text(userCountLabel)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Button {
                Task {
                    showDeactivatedUsers.toggle()
                    if showDeactivatedUsers {
                        await loadDeactivated()
                    } else {
                        deactivatedUsers = []
                    }
                }
            } label: {
                Text(showDeactivatedUsers ? "Hide deactivated" : "Show deactivated")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.accent)
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.md)
    }

    private var userList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                // Active users
                ForEach(userManager.clinicUsers) { user in
                    UserRow(
                        user: user,
                        isCurrentUser: user.id == authManager.currentUser?.id,
                        isDeactivated: false,
                        onEditRole: {
                            selectedUser = user
                            showEditRole = true
                        },
                        onDeactivate: {
                            selectedUser = user
                            showDeactivateConfirm = true
                        },
                        onReactivate: { /* not reachable for active users */ }
                    )
                }

                // Deactivated users
                if showDeactivatedUsers && !deactivatedUsers.isEmpty {
                    sectionHeader(title: "Deactivated")

                    ForEach(deactivatedUsers) { user in
                        UserRow(
                            user: user,
                            isCurrentUser: false,
                            isDeactivated: true,
                            onEditRole: { /* not shown for deactivated */ },
                            onDeactivate: { /* not shown for deactivated */ },
                            onReactivate: {
                                selectedUser = user
                                showReactivateConfirm = true
                            }
                        )
                    }
                }

                // Pending invitations — rendered ONCE, not per-user
                if !userManager.pendingInvitations.isEmpty {
                    sectionHeader(title: "Pending Invitations")

                    ForEach(userManager.pendingInvitations) { invite in
                        InvitationRow(
                            invitation: invite,
                            onCancel: {
                                invitationToCancel = invite
                                showCancelInvitationConfirm = true
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxxl)
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(AppFonts.title3)
                .foregroundColor(AppColors.textPrimary)
            Spacer()
        }
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xs)
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Computed
    // ══════════════════════════════════════════════════════

    private var userCountLabel: String {
        let active = userManager.clinicUsers.count
        let pending = userManager.pendingInvitations.count
        if pending == 0 {
            return "\(active) \(active == 1 ? "user" : "users")"
        }
        return "\(active) active • \(pending) pending"
    }

    private func availableRoles(excluding current: AppUser.UserRole) -> [AppUser.UserRole] {
        AppUser.UserRole.allCases.filter { $0 != current }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { userManager.errorMessage != nil },
            set: { if !$0 { userManager.errorMessage = nil } }
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Actions
    // ══════════════════════════════════════════════════════

    private func loadUsers() {
        guard let clinicID = authManager.effectiveClinicID else { return }
        Task {
            await userManager.loadUsers(clinicID: clinicID)
            if showDeactivatedUsers {
                await loadDeactivated()
            }
        }
    }

    private func loadDeactivated() async {
        guard let clinicID = authManager.effectiveClinicID else { return }
        do {
            let users = try await DatabaseService.shared.getDeactivatedClinicUsers(clinicID: clinicID)
            deactivatedUsers = users.sorted { $0.displayName < $1.displayName }
        } catch {
            print("Failed to load deactivated users: \(error)")
            userManager.errorMessage = "Could not load deactivated users: \(error.localizedDescription)"
        }
    }

    private func changeRole(to role: AppUser.UserRole) {
        guard let user = selectedUser,
              let admin = authManager.currentUser,
              let userID = user.id,
              let clinicID = authManager.effectiveClinicID
        else { return }

        Task {
            try? await userManager.updateUserRole(
                userID: userID,
                newRole: role,
                clinicID: clinicID,
                by: admin
            )
            selectedUser = nil
        }
    }

    private func performCancelInvitation(email: String) {
        guard let admin = authManager.currentUser,
              let clinicID = authManager.effectiveClinicID else { return }
        Task {
            try? await userManager.cancelInvitation(
                email: email,
                clinicID: clinicID,
                by: admin
            )
        }
    }

    private func deactivateUser() {
        guard let user = selectedUser,
              let admin = authManager.currentUser,
              let userID = user.id,
              let clinicID = authManager.effectiveClinicID
        else { return }

        Task {
            try? await userManager.deactivateUser(
                userID: userID,
                clinicID: clinicID,
                by: admin
            )
            selectedUser = nil
            if showDeactivatedUsers {
                await loadDeactivated()
            }
        }
    }

    private func reactivateUser() {
        guard let user = selectedUser,
              let admin = authManager.currentUser,
              let userID = user.id,
              let clinicID = authManager.effectiveClinicID
        else { return }

        Task {
            try? await userManager.reactivateUser(
                userID: userID,
                clinicID: clinicID,
                by: admin
            )
            selectedUser = nil
            if showDeactivatedUsers {
                await loadDeactivated()
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - User Row
// ══════════════════════════════════════════════════════

struct UserRow: View {

    let user: AppUser
    let isCurrentUser: Bool
    let isDeactivated: Bool
    var onEditRole: () -> Void
    var onDeactivate: () -> Void
    var onReactivate: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.lg) {

            UserAvatar(
                name: user.displayName,
                role: user.role,
                size: 44
            )
            .opacity(isDeactivated ? 0.5 : 1.0)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(user.displayName)
                        .font(AppFonts.bodySemibold)
                        .foregroundColor(
                            isDeactivated ? AppColors.textSecondary : AppColors.textPrimary
                        )

                    if isCurrentUser {
                        Text("(You)")
                            .font(AppFonts.footnote)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    if isDeactivated {
                        Text("• Deactivated")
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

            // Actions — hidden for current user, tailored to active state
            if !isCurrentUser {
                if isDeactivated {
                    Button(action: onReactivate) {
                        Text("Reactivate")
                            .font(AppFonts.captionSemibold)
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(
                                Capsule().stroke(AppColors.accent, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                } else {
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
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
        .cardShadow()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Invitation Row
// ══════════════════════════════════════════════════════

struct InvitationRow: View {

    let invitation: Invitation
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: "clock.fill")
                .font(.system(size: 20))
                .foregroundColor(AppColors.warning)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppColors.warningLight))

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(invitation.displayName)
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(invitation.email)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                RoleBadge(role: invitation.roleEnum)
            }

            Spacer()

            Button(action: onCancel) {
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

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview("Light") {
    NavigationStack {
        UserManagementView()
            .environmentObject(AuthManager.preview())
            .environmentObject(UserManager())
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        UserManagementView()
            .environmentObject(AuthManager.preview())
            .environmentObject(UserManager())
    }
    .preferredColorScheme(.dark)
}
