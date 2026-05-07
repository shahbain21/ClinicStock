//
//  MainTabView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain
//
//  LAYOUT FIX:
//  - Tab bar now has a top divider line + softer shadow to better
//    separate it from the content above. Previously the shadow alone
//    was too subtle against dark backgrounds.
//
//  PRIOR FIXES (carried forward):
//  - Listener lifecycle removed. RootView's .task(id:) owns it.
//  - Real tabs wired: DashboardView, InventoryListView, ScanTabView,
//    SettingsView.
//  - HistoryPlaceholder remains as a stub until full History view lands.
//  - Preview uses AuthManager.preview().
//

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @EnvironmentObject var tabRouter: TabRouter

    var body: some View {
        ZStack(alignment: .bottom) {

            TabView(selection: tabSelectionBinding) {

                DashboardView()
                    .tag(0)

                InventoryListView()
                    .tag(1)

                ScanTabView()
                    .tag(2)

                HistoryView()
                    .tag(3)

                SettingsView()
                    .tag(4)
            }

            CustomTabBar(selectedTab: tabSelectionBinding)
        }
        .ignoresSafeArea(.keyboard)
    }

    /// Bridge between TabView's Int-tag selection and TabRouter's
    /// strongly-typed enum. Keeps both views and router in sync.
    private var tabSelectionBinding: Binding<Int> {
        Binding(
            get: { tabRouter.selectedTab.rawValue },
            set: { tabRouter.selectedTab = TabRouter.Tab(rawValue: $0) ?? .dashboard }
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Custom Tab Bar
// ══════════════════════════════════════════════════════

struct CustomTabBar: View {

    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            // Top divider — visual anchor separating from content above
            Rectangle()
                .fill(AppColors.border.opacity(0.3))
                .frame(height: 1)

            HStack {
                tabButton(icon: "chart.bar.fill", title: "Dashboard", tab: 0)
                // Inventory tab removed — InventoryListView is now
                // reached via Dashboard stat-card taps only. Keeps the
                // tag (1) so TabRouter.openInventory still works to
                // switch internal state.
                tabButton(icon: "barcode.viewfinder", title: "Scan", tab: 2)
                tabButton(icon: "clock.fill", title: "History", tab: 3)
                tabButton(icon: "gearshape.fill", title: "Settings", tab: 4)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(
            AppColors.tabBarBackground
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
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
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    MainTabView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(UserManager())
        .environmentObject(HCPCSSearchService())
        .environmentObject(TabRouter())
}
