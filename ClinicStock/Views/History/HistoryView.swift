//
//  HistoryView.swift
//  ClinicStock
//
//  Full history log view with search, filter pills, pagination, and
//  role-gated CSV export.
//
//  FILTER PILLS (Option C layout):
//
//    All        — no filter
//    Checkouts  — quantityUpdate where updateType = "checkout"
//    Restocks   — quantityUpdate where updateType = "restock", plus added
//    Edits      — infoUpdate
//    Users      — userCreated, userUpdated (admin-only)
//
//  Deletions and stock alerts live under "All" only. They're rare and
//  shouldn't drown out primary views.
//
//  Users pill is hidden for non-admins per role-gating. Staff/editor/
//  manager users see 4 pills.
//
//  Checkout vs Restock distinction requires the `updateType` field on
//  logs. InventoryManager writes this from now on — older logs (before
//  this change) will only appear under "All".
//

import SwiftUI
import FirebaseFirestore

struct HistoryView: View {

    @EnvironmentObject var authManager: AuthManager

    @State private var logs: [HistoryLog] = []
    @State private var lastCursor: DocumentSnapshot? = nil
    @State private var hasMore: Bool = false

    @State private var isLoadingInitial = false
    @State private var isLoadingMore = false
    @State private var loadError: String? = nil

    @State private var searchText = ""
    @State private var selectedFilter: LogFilter = .all

    @State private var csvToShare: CSVShareItem? = nil

    enum LogFilter: Hashable {
        case all
        case checkouts
        case restocks
        case edits
        case users

        var title: String {
            switch self {
            case .all:       return "All"
            case .checkouts: return "Checkouts"
            case .restocks:  return "Restocks"
            case .edits:     return "Edits"
            case .users:     return "Users"
            }
        }

        // Action values to filter on (Firestore 'in' query). Nil = no
        // action-based filter.
        var actionValues: [String]? {
            switch self {
            case .all:       return nil
            case .checkouts: return ["quantityUpdate"]
            case .restocks:  return ["quantityUpdate", "added"]
            case .edits:     return ["infoUpdate"]
            case .users:     return ["userCreated", "userUpdated"]
            }
        }

        // Secondary field filter — used to split quantityUpdate logs
        // into checkouts vs restocks based on the denormalized field.
        var updateTypeValue: String? {
            switch self {
            case .checkouts: return "checkout"
            case .restocks:  return "restock"
            default:         return nil
            }
        }
    }

    private var canExport: Bool {
        PermissionManager.canExportCSV(role: authManager.currentUser?.role ?? .staff)
    }

    private var isAdmin: Bool {
        authManager.currentUser?.role == .admin
    }

    // Users pill is admin-only. Everyone sees All / Checkouts / Restocks / Edits.
    private var availableFilters: [LogFilter] {
        var filters: [LogFilter] = [.all, .checkouts, .restocks, .edits]
        if isAdmin {
            filters.append(.users)
        }
        return filters
    }

    // Client-side search over loaded pages.
    private var visibleLogs: [HistoryLog] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return logs }

        let query = trimmed.lowercased()
        return logs.filter {
            $0.itemName.lowercased().contains(query) ||
            $0.details.lowercased().contains(query) ||
            $0.userName.lowercased().contains(query)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Body
    // ══════════════════════════════════════════════════════

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBlock
                content
            }
            .appBackground()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationBell()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if canExport && !logs.isEmpty {
                    exportBar
                }
            }
            .sheet(item: $csvToShare) { item in
                ShareSheet(activityItems: [item.url])
            }
            .task {
                if logs.isEmpty {
                    await loadInitial()
                }
            }
            .refreshable {
                await loadInitial()
            }
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Header (search + filter pills)
    // ══════════════════════════════════════════════════════

    private var headerBlock: some View {
        VStack(spacing: AppSpacing.md) {
            AppSearchBar(text: $searchText, placeholder: "Search history")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(availableFilters, id: \.self) { filter in
                        FilterPill(
                            title: filter.title,
                            count: nil,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                            }
                            Task {
                                await loadInitial()
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.horizontal, -AppSpacing.lg)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
        .background(
            AppColors.background
                .overlay(
                    Rectangle()
                        .fill(AppColors.border.opacity(0.3))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Content
    // ══════════════════════════════════════════════════════

    @ViewBuilder
    private var content: some View {
        if isLoadingInitial && logs.isEmpty {
            Spacer()
            ProgressView("Loading history...")
                .foregroundColor(AppColors.textSecondary)
            Spacer()

        } else if let error = loadError, logs.isEmpty {
            Spacer()
            errorState(message: error)
            Spacer()

        } else if visibleLogs.isEmpty && !searchText.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "magnifyingglass",
                title: "No Matches",
                message: "Nothing loaded so far matches \"\(searchText)\". Try loading more or a different search."
            )
            Spacer()

        } else if logs.isEmpty {
            Spacer()
            EmptyStateView(
                icon: "clock",
                title: emptyTitle,
                message: emptyMessage
            )
            Spacer()

        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.sm) {
                    // Inline error banner — shown even when we have logs,
                    // so the user knows if their most recent filter query
                    // failed while stale results are still visible.
                    if let error = loadError {
                        errorBanner(message: error)
                    }

                    ForEach(visibleLogs) { log in
                        HistoryLogCard(log: log)
                    }

                    if hasMore {
                        loadMoreRow
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Query failed")
                    .font(AppFonts.captionSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(message)
                    .font(AppFonts.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
            }
            Spacer()
            Button("Retry") {
                Task { await loadInitial() }
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var emptyTitle: String {
        switch selectedFilter {
        case .all:       return "No Activity Yet"
        case .checkouts: return "No Checkouts"
        case .restocks:  return "No Restocks"
        case .edits:     return "No Edits"
        case .users:     return "No User Activity"
        }
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .all:
            return "Checkouts, edits, and other changes will appear here."
        case .checkouts:
            return "Barcode scans and stock checkouts will appear here."
        case .restocks:
            return "Added items and stock replenishments will appear here."
        case .edits:
            return "Edits to item info (names, HCPCS codes, thresholds) will appear here."
        case .users:
            return "Invitations, role changes, and user status updates will appear here."
        }
    }

    private var loadMoreRow: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack {
                if isLoadingMore {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "arrow.down.circle")
                    Text("Load more")
                }
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColors.accent.opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(isLoadingMore)
        .padding(.top, AppSpacing.sm)
    }

    private func errorState(message: String) -> some View {
        let isIndexError = message.localizedCaseInsensitiveContains("requires an index")

        return VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(AppColors.warning)
            Text(isIndexError ? "Database Index Building" : "Couldn't load history")
                .font(AppFonts.bodySemibold)
                .foregroundColor(AppColors.textPrimary)
            Text(isIndexError
                ? "The database is preparing for this filter. If you just set up the app, an admin needs to create a Firestore composite index — check the Xcode console for the setup URL. This takes 1-2 minutes after creation."
                : message)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)
            Button("Try Again") {
                Task { await loadInitial() }
            }
            .font(AppFonts.captionSemibold)
            .foregroundColor(AppColors.accent)
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Export bar
    // ══════════════════════════════════════════════════════

    private var exportBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(AppColors.border.opacity(0.3))
                .frame(height: 1)

            Button(action: exportCSV) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Export CSV")
                }
                .font(AppFonts.bodySemibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .fill(AppColors.accent)
                )
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(
            AppColors.background
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        )
    }

    // ══════════════════════════════════════════════════════
    // MARK: - Loading
    // ══════════════════════════════════════════════════════

    private func loadInitial() async {
        // Aggregate mode: query without clinicID filter (cross-clinic).
        // Single-clinic mode: filter by effectiveClinicID.
        let clinicID = authManager.effectiveClinicID

        // For non-admin users who somehow have no clinicID, abort —
        // they shouldn't be in this view anyway.
        if !authManager.isAggregateMode && clinicID == nil {
            return
        }

        isLoadingInitial = true
        loadError = nil
        logs = []
        lastCursor = nil
        hasMore = false
        defer { isLoadingInitial = false }

        do {
            let page: DatabaseService.LogsPage
            if authManager.isAggregateMode {
                page = try await DatabaseService.shared.getAllLogsPage(
                    pageSize: 50,
                    startAfter: nil,
                    actions: selectedFilter.actionValues,
                    updateType: selectedFilter.updateTypeValue
                )
            } else {
                page = try await DatabaseService.shared.getClinicLogsPage(
                    clinicID: clinicID!,
                    pageSize: 50,
                    startAfter: nil,
                    actions: selectedFilter.actionValues,
                    updateType: selectedFilter.updateTypeValue
                )
            }

            logs = page.logs
            lastCursor = page.lastDocument
            hasMore = page.hasMore
        } catch {
            print("[HistoryView] loadInitial error: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func loadMore() async {
        let clinicID = authManager.effectiveClinicID
        if !authManager.isAggregateMode && clinicID == nil { return }

        guard let cursor = lastCursor, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page: DatabaseService.LogsPage
            if authManager.isAggregateMode {
                page = try await DatabaseService.shared.getAllLogsPage(
                    pageSize: 50,
                    startAfter: cursor,
                    actions: selectedFilter.actionValues,
                    updateType: selectedFilter.updateTypeValue
                )
            } else {
                page = try await DatabaseService.shared.getClinicLogsPage(
                    clinicID: clinicID!,
                    pageSize: 50,
                    startAfter: cursor,
                    actions: selectedFilter.actionValues,
                    updateType: selectedFilter.updateTypeValue
                )
            }

            logs.append(contentsOf: page.logs)
            lastCursor = page.lastDocument
            hasMore = page.hasMore
        } catch {
            loadError = error.localizedDescription
        }
    }

    // ══════════════════════════════════════════════════════
    // MARK: - CSV Export
    // ══════════════════════════════════════════════════════

    private func exportCSV() {
        let rows: [String] = visibleLogs.map { log in
            let ts = ISO8601DateFormatter().string(from: log.timestamp)
            let fields = [
                ts,
                csvEscape(log.action.displayName),
                csvEscape(log.itemName),
                csvEscape(log.userName),
                csvEscape(log.previousValue),
                csvEscape(log.newValue),
                csvEscape(log.details)
            ]
            return fields.joined(separator: ",")
        }

        let header = "Timestamp,Action,Item,User,Previous,New,Details"
        let csv = ([header] + rows).joined(separator: "\n")

        do {
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "clinicstock-history-\(Int(Date().timeIntervalSince1970)).csv"
            let url = tempDir.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvToShare = CSVShareItem(url: url)
        } catch {
            loadError = "Couldn't create export: \(error.localizedDescription)"
        }
    }

    private func csvEscape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if !needsQuoting { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Log Card
// ══════════════════════════════════════════════════════

struct HistoryLogCard: View {
    let log: HistoryLog

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: log.action.icon)
                .font(.system(size: 18))
                .foregroundColor(actionColor)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(actionColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(log.itemName)
                    .font(AppFonts.bodySemibold)
                    .foregroundColor(AppColors.textPrimary)

                Text(log.details)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.xs) {
                    Text(log.userName)
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textTertiary)
                    Text("·")
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textTertiary)
                    Text(log.timestamp.formatted(.relative(presentation: .named)))
                        .font(AppFonts.footnote)
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColors.cardBackground)
        )
    }

    private var actionColor: Color {
        switch log.action {
        case .added: return AppColors.success
        case .deleted: return AppColors.danger
        case .quantityUpdate, .infoUpdate: return AppColors.accent
        case .barcodeScan: return AppColors.accent
        case .userCreated, .userUpdated: return AppColors.warning
        case .stockAlert: return AppColors.warning
        }
    }
}

// ══════════════════════════════════════════════════════
// MARK: - Share helpers
// ══════════════════════════════════════════════════════

private struct CSVShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

// ══════════════════════════════════════════════════════
// MARK: - Preview
// ══════════════════════════════════════════════════════

#Preview {
    HistoryView()
        .environmentObject(AuthManager.preview())
        .environmentObject(InventoryManager())
}
