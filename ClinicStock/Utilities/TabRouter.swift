//
//  TabRouter.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/30/26.
//


//
//  TabRouter.swift
//  ClinicStock
//
//  Cross-tab navigation coordinator. Lets any view request a tab
//  switch (and optionally pre-apply a filter) without prop-drilling
//  state through every parent.
//
//  Used by:
//   - DashboardView taps that drill into Inventory or History
//   - Future: notification taps, deep links, etc.
//
//  Usage:
//   In MainTabView: bind selectedTab to router.selectedTab so the
//   tab bar reflects router changes.
//
//   Anywhere else: read TabRouter from environment and call
//   router.openInventory(filter: .low) etc.
//

import Foundation
import Combine

@MainActor
final class TabRouter: ObservableObject {

    enum Tab: Int {
        case dashboard = 0
        case inventory = 1
        case scan = 2
        case history = 3
        case settings = 4
    }

    /// Inventory has a few stock filters. When dashboard requests an
    /// Inventory drill-in, it can pre-apply one. The Inventory view
    /// reads this on appear, applies it, then clears it (so the next
    /// time the user hand-navigates the filter isn't auto-overwritten).
    enum InventoryFilterRequest: String {
        case all = "All"
        case low = "Low"
        case out = "Out"
    }

    @Published var selectedTab: Tab = .dashboard

    /// Pending filter to apply when Inventory tab opens. The Inventory
    /// view consumes this and sets it to nil to prevent re-application
    /// on subsequent appearances.
    @Published var pendingInventoryFilter: InventoryFilterRequest? = nil

    func openInventory(filter: InventoryFilterRequest? = nil) {
        pendingInventoryFilter = filter
        selectedTab = .inventory
    }

    func openHistory() {
        selectedTab = .history
    }

    /// Called by InventoryListView when it has consumed and applied
    /// the pending filter. Without this, switching to another tab and
    /// back would re-apply the same filter.
    func consumeInventoryFilter() {
        pendingInventoryFilter = nil
    }
}