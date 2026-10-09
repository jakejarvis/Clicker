import SwiftUI

/// Popover content for the Apps button: a search field over the Apple TV's
/// app list, with the starred apps and the last few launched ones on top.
/// Every row has a star to pin it (shown while hovered, kept while starred);
/// the row's context menu offers the same. A system `Menu` cannot
/// search or group forty apps comfortably, so the list is custom, in the
/// same style as the device picker. Arrow keys move the highlight, Return
/// launches it, and typing filters; while a query is typed the top match is
/// highlighted so Return launches it straight away.
///
/// The panel stays the key window under the popover, so arrows and Return
/// ride a local key monitor (the text field never sees them) and Esc is
/// handled by the panel's own monitor through `RemoteController.handleEscape`.
struct AppPickerView: View {
    let controller: RemoteController

    @State private var keyMonitor: Any?

    @State private var query = ""
    @State private var highlightedRowID: String?
    /// Set only by the arrow keys, so the list scrolls to follow the
    /// keyboard but never jumps under the pointer.
    @State private var keyboardRowID: String?
    @FocusState private var isSearchFocused: Bool

    private static let maxListHeight: CGFloat = 300

    var body: some View {
        let rows = rows
        VStack(spacing: 6) {
            searchField
            if controller.apps.isEmpty {
                placeholder(controller.isLoadingApps ? "Loading apps…" : "No apps found")
            } else if rows.isEmpty {
                placeholder("No Results")
            } else {
                list(rows)
            }
        }
        .padding(6)
        .frame(width: MenuBarView.panelWidth - 28)
        .onAppear {
            DispatchQueue.main.async { isSearchFocused = true }
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: query) {
            highlightedRowID = isSearching ? self.rows.first?.id : nil
        }
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let id: String
        let app: AppleTVApp
        /// Header drawn above this row, for the first row of a section.
        let header: String?
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The visible rows in order: matches while searching, otherwise
    /// Favorites, then Recent (without the starred ones, so a pinned app is
    /// not twice at the top), then every app. An app can appear in more
    /// than one section, so row ids carry the section.
    private var rows: [Row] {
        if isSearching {
            let needle = query.trimmingCharacters(in: .whitespaces)
            let matches = controller.apps.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            let prefixed = matches.filter { $0.name.localizedCaseInsensitiveStartsWith(needle) }
            let rest = matches.filter { !$0.name.localizedCaseInsensitiveStartsWith(needle) }
            return (prefixed + rest).map { Row(id: "match.\($0.id)", app: $0, header: nil) }
        }
        let favorites = controller.favoriteApps
        let recents = controller.recentApps.filter { !favorites.contains($0) }
        var rows = favorites.enumerated().map { index, app in
            Row(id: "favorite.\(app.id)", app: app, header: index == 0 ? "Favorites" : nil)
        }
        rows += recents.enumerated().map { index, app in
            Row(id: "recent.\(app.id)", app: app, header: index == 0 ? "Recents" : nil)
        }
        let pinned = !favorites.isEmpty || !recents.isEmpty
        rows += controller.apps.enumerated().map { index, app in
            Row(id: "all.\(app.id)", app: app, header: index == 0 && pinned ? "All Apps" : nil)
        }
        return rows
    }

    // MARK: - Pieces

    private var searchField: some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(launchHighlighted)
            if controller.isLoadingApps {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Button {
                    controller.refreshApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh the app list")
                .accessibilityLabel("Refresh apps")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.55), in: shape)
        .overlay(shape.strokeBorder(.separator.opacity(0.6), lineWidth: 1))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
    }

    private func list(_ rows: [Row]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        if let header = row.header {
                            HStack {
                                Text(header)
                                if header == "Recents" {
                                    Spacer()
                                    Button("Clear") {
                                        highlightedRowID = nil
                                        controller.clearRecents()
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tertiary)
                                    .help("Forget the recently opened apps")
                                    .accessibilityLabel("Clear recent apps")
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, row.id == rows.first?.id ? 4 : 8)
                            .padding(.bottom, 2)
                        }
                        AppRow(
                            app: row.app,
                            isHighlighted: row.id == highlightedRowID,
                            isFavorite: controller.isFavorite(row.app)
                        ) {
                            launch(row.app)
                        } onToggleFavorite: {
                            controller.toggleFavorite(row.app)
                        } onHover: { hovering in
                            if hovering {
                                highlightedRowID = row.id
                            } else if highlightedRowID == row.id {
                                highlightedRowID = nil
                            }
                        }
                        .id(row.id)
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
            .onChange(of: keyboardRowID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                switch event.keyCode {
                case 126: return moveHighlight(by: -1)
                case 125: return moveHighlight(by: 1)
                case 36, 76:  // Return, keypad Enter
                    launchHighlighted()
                    return true
                default: return false
                }
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - Actions

    @discardableResult
    private func moveHighlight(by offset: Int) -> Bool {
        let rows = rows
        guard !rows.isEmpty else { return false }
        let current = rows.firstIndex { $0.id == highlightedRowID }
        let next: Int
        if let current {
            next = min(max(current + offset, 0), rows.count - 1)
        } else {
            next = offset > 0 ? 0 : rows.count - 1
        }
        highlightedRowID = rows[next].id
        keyboardRowID = rows[next].id
        return true
    }

    private func launchHighlighted() {
        guard let app = rows.first(where: { $0.id == highlightedRowID })?.app else { return }
        launch(app)
    }

    private func launch(_ app: AppleTVApp) {
        controller.launch(app)
        controller.isAppPickerPresented = false
    }
}

/// One app: the name launches it, the star at the trailing edge pins it.
/// The star is a sibling of the launch button, not nested in it, so a
/// click on it never launches the app.
private struct AppRow: View {
    let app: AppleTVApp
    let isHighlighted: Bool
    let isFavorite: Bool
    let action: () -> Void
    let onToggleFavorite: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.innerCornerRadius - 4, style: .continuous)
        HStack(spacing: 0) {
            Button(action: action) {
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(app.name)
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(starStyle)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isFavorite || isHighlighted ? 1 : 0)
            .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            .accessibilityLabel(isFavorite ? "Remove \(app.name) from Favorites" : "Add \(app.name) to Favorites")
        }
        .padding(.trailing, 2)
        .background(shape.fill(isHighlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear)))
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .focusEffectDisabled()
        .contentShape(shape)
        .onHover(perform: onHover)
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
        }
    }

    /// A starred app's star is yellow until its row is highlighted, where
    /// everything is white on the selection fill.
    private var starStyle: AnyShapeStyle {
        if isHighlighted { return AnyShapeStyle(.white) }
        return isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary)
    }
}

extension String {
    fileprivate func localizedCaseInsensitiveStartsWith(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
    }
}
