//
//  DashboardView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/18/26.
//
//  FIXES:
//  - Removed the stray `import Foundation` that appeared inside the file
//    body (SwiftUI already brings Foundation transitively).
//  - Duplicate file header removed.
//  - Empty button actions replaced with explicit TODO prints so it's
//    clear they're stubs, not silent dead UI. Proper cross-tab nav
//    is a separate follow-up.
//  - Added a #Preview.
//
//  DEFERRED:
//  - Multi-clinic overview (mockup shows multiple clinics — single
//    clinic for now per design decision).
//  - Cross-tab navigation for "View Alerts" / "View All" — requires a
//    shared NavigationCoordinator object that doesn't exist yet.
//

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager
    @EnvironmentObject var tabRouter: TabRouter

    /// Cache of clinicID → clinic name. Populated on appear in
    /// aggregate mode so the per-clinic breakdown can show real names
    /// instead of "Loading…". Refreshed when inventory items change
    /// (in case a new clinic appeared in the data).
    @State private var clinicNamesCache: [String: String] = [:]

    /// Sheet presentation for tapped activity rows. We open ItemDetail
    /// in a sheet rather than trying to push it onto the Inventory
    /// tab's NavigationStack — too complex from outside that stack,
    /// and a sheet is a more direct UX for "I tapped something on
    /// Dashboard, show me the thing."
    @State private var activitySheetItem: InventoryItem? = nil

    var totalQuantity: Int {
        inventoryManager.items.reduce(0) { $0 + $1.quantity }
    }

    var lowStockCount: Int {
        inventoryManager.items.filter { $0.isLowStock && $0.quantity > 0 }.count
    }

    var outOfStockCount: Int {
        inventoryManager.items.filter { $0.quantity <= 0 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.xl) {

                    // ── Back to All Clinics pill ──
                    //
                    // Shown only when a platform admin has switched
                    // INTO a single clinic. Switching clinics is a
                    // global mode change, not page navigation, so we
                    // can't use a regular back button — but the user
                    // still wants a way to return to the aggregate
                    // view. This pill makes that path discoverable
                    // without requiring them to find it via Settings.
                    if authManager.isPlatformAdmin && !authManager.isAggregateMode {
                        backToAllClinicsPill
                            .padding(.horizontal, AppSpacing.lg)
                    }

                    // ── Stats Row (3 cards, all tappable) ──
                    //
                    // User testing: testers wanted these to be drill-in
                    // shortcuts. Each card now navigates to the Inventory
                    // tab with the corresponding filter pre-applied.
                    HStack(spacing: AppSpacing.md) {
                        Button {
                            tabRouter.openInventory(filter: .all)
                        } label: {
                            DashboardStatCard(
                                title: "Total Items",
                                value: formatNumber(totalQuantity),
                                color: AppColors.primary
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            tabRouter.openInventory(filter: .low)
                        } label: {
                            DashboardStatCard(
                                title: "Low Stock",
                                value: "\(lowStockCount)",
                                color: AppColors.warning
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            tabRouter.openInventory(filter: .out)
                        } label: {
                            DashboardStatCard(
                                title: "Out of Stock",
                                value: "\(outOfStockCount)",
                                color: AppColors.danger
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    // ── Recent Activity ──
                    if !inventoryManager.recentLogs.isEmpty {
                        VStack(spacing: AppSpacing.md) {
                            AppSectionHeader(
                                title: "Recent Activity",
                                action: "View All"
                            ) {
                                tabRouter.openHistory()
                            }

                            VStack(spacing: AppSpacing.sm) {
                                ForEach(inventoryManager.recentLogs.prefix(5)) { log in
                                    RecentActivityRow(log: log)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            handleActivityTap(log: log)
                                        }
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    // ── Clinic Overview ──
                    // Single-clinic for now. Multi-clinic is a future
                    // feature — requires AppUser supporting multiple clinic
                    // memberships and cross-clinic activity queries.
                    // ── Clinic context card ──
                    //
                    // In single-clinic mode: shows the clinic the user
                    // is currently viewing. In aggregate mode: replaced
                    // by an "All Clinics" header + per-clinic breakdown
                    // (read-only summary; switching is via Settings per
                    // earlier design decision).
                    if authManager.isAggregateMode {
                        aggregateClinicsBreakdown
                            .padding(.horizontal, AppSpacing.lg)
                    } else if let clinic = authManager.currentClinic {
                        VStack(spacing: AppSpacing.md) {
                            AppSectionHeader(title: "Clinic Overview")

                            AppCard {
                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(AppColors.accent)

                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        Text(clinic.name)
                                            .font(AppFonts.bodySemibold)
                                            .foregroundColor(AppColors.textPrimary)
                                        Text(clinic.fullAddress)
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }

                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                }
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, 100)
            }
            .appBackground()
            .navigationTitle(authManager.isAggregateMode ? "All Clinics" : "Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                if authManager.isAggregateMode {
                    await inventoryManager.loadAggregateInventory()
                }
                // Single-clinic mode auto-refreshes via the listener.
            }
            .task(id: aggregateClinicSignature) {
                // Resolve clinicID → clinic name for the breakdown card.
                // Only runs in aggregate mode (and when the set of
                // clinics in the loaded data changes).
                guard authManager.isAggregateMode else { return }
                await loadClinicNames()
            }
            .sheet(item: $activitySheetItem) { item in
                NavigationStack {
                    ItemDetailView(item: item)
                }
            }
        }
    }

    /// Tapped activity row → present the corresponding item's detail.
    /// We look up the item by ID from the currently-loaded inventory.
    /// In single-clinic mode this is the listener's items; in aggregate
    /// mode it's the cross-clinic snapshot.
    ///
    /// Logs may reference items that have since been deleted or that
    /// belong to a clinic not in the current view (in single-clinic
    /// mode after switching away from where the activity originated).
    /// In those cases the lookup returns nil and we silently no-op —
    /// the user can tap "View All" to find the activity in History.
    private func handleActivityTap(log: HistoryLog) {
        guard let item = inventoryManager.items.first(where: { $0.id == log.itemID }) else {
            print("[Dashboard] tap on activity with no matching item: \(log.itemID)")
            return
        }
        activitySheetItem = item
    }

    /// Signature that changes when the set of clinic IDs in the
    /// currently-loaded inventory changes. Used as task(id:) so we
    /// only re-resolve clinic names when needed.
    private var aggregateClinicSignature: String {
        let ids = Set(inventoryManager.items.map { $0.clinicID })
        return ids.sorted().joined(separator: "|")
    }

    private func loadClinicNames() async {
        let ids = Set(inventoryManager.items.map { $0.clinicID })
            .filter { !$0.isEmpty }
            .subtracting(clinicNamesCache.keys)
        guard !ids.isEmpty else { return }

        for clinicID in ids {
            if let clinic = try? await DatabaseService.shared.getClinic(clinicID: clinicID) {
                await MainActor.run {
                    self.clinicNamesCache[clinicID] = clinic.name
                }
            }
        }
    }

    /// Pill shown at the top of the dashboard when a platform admin
    /// is viewing a single clinic but came from aggregate mode. Tap
    /// puts them back into aggregate mode. Hidden for non-platform
    /// admins (regular users don't have aggregate access) and when
    /// already in aggregate mode (would be a no-op).
    private var backToAllClinicsPill: some View {
        Button {
            authManager.selectAggregateMode()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("All Clinics")
                    .font(AppFonts.captionSemibold)
            }
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                Capsule()
                    .fill(AppColors.accent.opacity(0.12))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    /// Aggregate-mode card listing each clinic with its current
    /// inventory metrics. Tapping a row switches into that clinic
    /// (single-clinic mode). The "Back to All Clinics" pill at the
    /// top of the dashboard provides the inverse action.
    private var aggregateClinicsBreakdown: some View {
        let perClinic = computePerClinicBreakdown()

        return VStack(spacing: AppSpacing.md) {
            AppSectionHeader(title: "By Location")

            if perClinic.isEmpty {
                AppCard {
                    Text("No inventory loaded yet — pull to refresh.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(perClinic, id: \.clinicID) { entry in
                    Button {
                        // Switch out of aggregate mode and into this
                        // clinic. selectClinic is async because it
                        // also fetches the Clinic doc to populate
                        // currentClinic — wrap in Task so the row
                        // tap doesn't have to be in an async context.
                        Task {
                            await authManager.selectClinic(entry.clinicID)
                        }
                    } label: {
                        AppCard {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "building.2")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.accent)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(AppColors.accent.opacity(0.15))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.clinicName)
                                        .font(AppFonts.bodySemibold)
                                        .foregroundColor(AppColors.textPrimary)
                                    Text("\(entry.itemCount) items · \(entry.totalStock) units")
                                        .font(AppFonts.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }

                                Spacer()

                                if entry.lowStockCount > 0 {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text("\(entry.lowStockCount)")
                                            .font(AppFonts.bodySemibold)
                                            .foregroundColor(AppColors.warning)
                                        Text("low")
                                            .font(AppFonts.footnote)
                                            .foregroundColor(AppColors.textTertiary)
                                    }
                                }

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Group the loaded inventory by clinicID and compute per-clinic
    /// summary stats.
    private func computePerClinicBreakdown() -> [PerClinicSummary] {
        let groups = Dictionary(grouping: inventoryManager.items) { $0.clinicID }
        return groups
            .filter { !$0.key.isEmpty }
            .map { (clinicID, items) in
                PerClinicSummary(
                    clinicID: clinicID,
                    clinicName: clinicNamesCache[clinicID] ?? "Loading…",
                    itemCount: items.count,
                    totalStock: items.map { $0.quantity }.reduce(0, +),
                    lowStockCount: items.filter { $0.isLowStock }.count
                )
            }
            .sorted { $0.clinicName < $1.clinicName }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Dashboard Stat Card (3-across style)
// ══════════════════════════════════════════════════════

struct DashboardStatCard: View {
    let title: String
    let value: String
    var color: Color = AppColors.primary

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textSecondary)

            Text(value)
                .font(AppFonts.quantityMedium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
        .cardShadow()
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Recent Activity Row
// ══════════════════════════════════════════════════════

struct RecentActivityRow: View {
    let log: HistoryLog

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: log.action.icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(log.itemName)
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(log.details)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(log.timestamp.timeAgoDisplay())
                .font(AppFonts.footnote)
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(AppColors.cardBackground)
        )
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Date formatting helper
//
// Lives here for now. When other views need relative timestamps, move
// this to a shared DateFormatting.swift utility file.
// ══════════════════════════════════════════════════════

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = Int(Date().timeIntervalSince(self))

        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 604800 {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Per-clinic summary (aggregate dashboard)
// ══════════════════════════════════════════════════════

struct PerClinicSummary: Identifiable {
    let clinicID: String
    let clinicName: String
    let itemCount: Int
    let totalStock: Int
    let lowStockCount: Int

    var id: String { clinicID }
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    DashboardView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
        .environmentObject(TabRouter())
}
