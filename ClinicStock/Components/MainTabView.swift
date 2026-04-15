//
//  MainTabView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/14/26.
//

//
//  MainTabView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  Main tab navigation after login.
//  Tabs shown depend on user role.
//

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Tab Content ──
            TabView(selection: $selectedTab) {

                // Tab 1: Dashboard
                DashboardPlaceholder()
                    .tag(0)

                // Tab 2: Inventory
                InventoryPlaceholder()
                    .tag(1)

                // Tab 3: Scanner
                ScannerPlaceholder()
                    .tag(2)

                // Tab 4: History
                HistoryPlaceholder()
                    .tag(3)

                // Tab 5: Settings
                SettingsPlaceholder()
                    .tag(4)
            }

            // ── Custom Tab Bar ──
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Custom Tab Bar (matches prototype)
// ══════════════════════════════════════════════════════

struct CustomTabBar: View {

    @Binding var selectedTab: Int
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        HStack {
            tabButton(icon: "chart.bar.fill", title: "Dashboard", tab: 0)
            tabButton(icon: "shippingbox.fill", title: "Inventory", tab: 1)
            tabButton(icon: "barcode.viewfinder", title: "Scan", tab: 2)
            tabButton(icon: "clock.fill", title: "History", tab: 3)
            tabButton(icon: "gearshape.fill", title: "Settings", tab: 4)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.xxl)
        .background(
            AppColors.tabBarBackground
                .shadow(
                    color: AppShadow.large.color,
                    radius: AppShadow.large.radius,
                    y: -AppShadow.large.y
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(icon: String, title: String, tab: Int) -> some View {
        Button(action: { selectedTab = tab }) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20))

                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(
                selectedTab == tab
                ? AppColors.tabBarActive
                : AppColors.tabBarInactive
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Placeholder Views
// Will be replaced with real views as we build them
// ══════════════════════════════════════════════════════

struct DashboardPlaceholder: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {

                    // Welcome
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Welcome back,")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)
                            Text(authManager.currentUser?.displayName ?? "User")
                                .font(AppFonts.title2)
                                .foregroundColor(AppColors.textPrimary)
                        }
                        Spacer()
                        RoleBadge(role: authManager.currentUser?.role ?? .staff)
                    }
                    .padding(.horizontal, AppSpacing.xl)

                    // Stats
                    HStack(spacing: AppSpacing.md) {
                        StatCard(
                            title: "Total Items",
                            value: "\(inventoryManager.items.reduce(0) { $0 + $1.quantity })"
                        )
                        StatCard(
                            title: "Low Stock",
                            value: "\(inventoryManager.lowStockItems.count)",
                            color: inventoryManager.lowStockItems.isEmpty
                                ? AppColors.success
                                : AppColors.danger
                        )
                    }
                    .padding(.horizontal, AppSpacing.xl)

                    // Low stock alert
                    if !inventoryManager.lowStockItems.isEmpty {
                        LowStockBanner(count: inventoryManager.lowStockItems.count)
                            .padding(.horizontal, AppSpacing.xl)
                    }

                    // Recent activity
                    if !inventoryManager.recentLogs.isEmpty {
                        AppSectionHeader(title: "Recent Activity")
                            .padding(.horizontal, AppSpacing.xl)

                        VStack(spacing: AppSpacing.sm) {
                            ForEach(
                                inventoryManager.recentLogs.prefix(5)
                            ) { log in
                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: log.action.icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(AppColors.accent)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(log.details)
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.textPrimary)
                                            .lineLimit(1)
                                        Text(log.userName)
                                            .font(AppFonts.footnote)
                                            .foregroundColor(AppColors.textTertiary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, AppSpacing.xl)
                            }
                        }
                    }
                }
                .padding(.top, AppSpacing.lg)
            }
            .appBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct InventoryPlaceholder: View {
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(inventoryManager.items) { item in
                        InventoryRowView(item: item)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
            .appBackground()
            .navigationTitle("Inventory")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if inventoryManager.items.isEmpty {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "No Items",
                        message: "Start by adding inventory items"
                    )
                }
            }
        }
    }
}

struct ScannerPlaceholder: View {
    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "barcode.viewfinder",
                title: "Scanner",
                message: "Scan barcodes to check out or look up items"
            )
            .appBackground()
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct HistoryPlaceholder: View {
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        NavigationStack {
            List(inventoryManager.recentLogs) { log in
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: log.action.icon)
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.itemName)
                            .font(AppFonts.bodySemibold)
                        Text(log.details)
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                        Text(log.userName)
                            .font(AppFonts.footnote)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
            .listStyle(.plain)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if inventoryManager.recentLogs.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No History",
                        message: "Activity will appear here"
                    )
                }
            }
        }
    }
}

struct SettingsPlaceholder: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

    var body: some View {
        NavigationStack {
            List {
                // Profile
                Section {
                    HStack(spacing: AppSpacing.lg) {
                        UserAvatar(
                            name: authManager.currentUser?.displayName ?? "U",
                            role: authManager.currentUser?.role ?? .staff,
                            size: 50
                        )

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(authManager.currentUser?.displayName ?? "User")
                                .font(AppFonts.bodySemibold)
                            Text(authManager.currentUser?.email ?? "")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.textSecondary)
                            RoleBadge(role: authManager.currentUser?.role ?? .staff)
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                }

                // Clinic
                Section("Clinic") {
                    LabeledContent(
                        "Name",
                        value: authManager.currentClinic?.name ?? "—"
                    )
                    LabeledContent(
                        "Location",
                        value: authManager.currentClinic?.fullAddress ?? "—"
                    )
                }

                // Admin only
                if authManager.currentUser?.role == .admin {
                    Section("Admin") {
                        NavigationLink {
                            // UserManagementView() — will build
                            Text("User Management")
                        } label: {
                            Label("User Management", systemImage: "person.2.fill")
                        }
                    }
                }

                // Sign Out
                Section {
                    Button(action: signOut) {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(AppFonts.bodySemibold)
                                .foregroundColor(AppColors.danger)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func signOut() {
        inventoryManager.stopListening()
        authManager.signOut()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    MainTabView()
        .environmentObject(AuthManager())
        .environmentObject(InventoryManager())
}
