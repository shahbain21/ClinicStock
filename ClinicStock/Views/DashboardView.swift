//
//  DashboardView.swift
//  ClinicStock
//
//  Created by Mohamed Shahbain on 4/18/26.
//

//
//  DashboardView.swift
//  ClinicStock
//

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var inventoryManager: InventoryManager

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

                    // ── Stats Row (3 cards) ──
                    HStack(spacing: AppSpacing.md) {
                        DashboardStatCard(
                            title: "Total Items",
                            value: formatNumber(totalQuantity),
                            color: AppColors.primary
                        )
                        DashboardStatCard(
                            title: "Low Stock",
                            value: "\(lowStockCount)",
                            color: AppColors.warning
                        )
                        DashboardStatCard(
                            title: "Out of Stock",
                            value: "\(outOfStockCount)",
                            color: AppColors.danger
                        )
                    }
                    .padding(.horizontal, AppSpacing.lg)

                    // ── Low Stock Alert Banner ──
                    if lowStockCount > 0 {
                        LowStockBanner(count: lowStockCount) {
                            // Navigate to inventory with Low filter
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    // ── Recent Activity ──
                    if !inventoryManager.recentLogs.isEmpty {
                        VStack(spacing: AppSpacing.md) {
                            AppSectionHeader(
                                title: "Recent Activity",
                                action: "View All"
                            ) {
                                // Navigate to History tab
                            }

                            VStack(spacing: AppSpacing.sm) {
                                ForEach(inventoryManager.recentLogs.prefix(5)) { log in
                                    RecentActivityRow(log: log)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }

                    // ── Clinic Overview ──
                    if let clinic = authManager.currentClinic {
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
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBell()
                }
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// ── Dashboard Stat Card (3-across style) ──
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

// ── Recent Activity Row ──
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

import Foundation

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = Int(Date().timeIntervalSince(self))

        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 604800 { return "\(seconds / 86400) day\(seconds / 86400 == 1 ? "" : "s") ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
}
