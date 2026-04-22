//
//  MainTabView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  FIXES:
//  - Listener lifecycle removed. RootView's .task(id:) is now the single
//    owner of startListening/stopListening.
//  - DashboardPlaceholder removed — wires in the real DashboardView.
//  - SettingsPlaceholder extracted to SettingsView.swift.
//  - ScannerPlaceholder replaced with real ScanTabView — fast-checkout
//    flow for staff (scan → confirm → done).
//  - Unused @EnvironmentObject on CustomTabBar removed.
//  - Preview uses AuthManager.preview().
//
//  HistoryPlaceholder still lives here as a stub. Replace with a real
//  HistoryView (paginated, filterable) when scoped as its own feature.
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

                DashboardView()
                    .tag(0)

                InventoryListView()
                    .tag(1)

                ScanTabView()
                    .tag(2)

                HistoryPlaceholder()
                    .tag(3)

                SettingsView()
                    .tag(4)
            }

            // ── Custom Tab Bar ──
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Custom Tab Bar
// ══════════════════════════════════════════════════════

struct CustomTabBar: View {

    @Binding var selectedTab: Int

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
                .shadow(color: .black.opacity(0.3), radius: 16, y: -8)
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
// MARK: - Stub tabs (awaiting real implementations)
// ══════════════════════════════════════════════════════

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
            .navigationTitle("Recent Activity")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if inventoryManager.recentLogs.isEmpty {
                    EmptyStateView(
                        icon: "clock",
                        title: "No Recent Activity",
                        message: "Checkouts and changes will appear here"
                    )
                }
            }
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    MainTabView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(UserManager())
        .environmentObject(HCPCSSearchService())
}
