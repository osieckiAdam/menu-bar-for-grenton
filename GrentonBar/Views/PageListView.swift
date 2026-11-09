import SwiftUI

/// Pages (rooms) as collapsible rows; a page opens into its sections, lights and shutters.
struct PageListView: View {
    let home: HomeModel
    /// Names of the expanded pages, one per line; a view preference, not data.
    @AppStorage("expandedPages") private var expandedRaw = ""
    @State private var contentHeight: CGFloat = 0

    private static let maxHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(home.pages) { page in
                    PageRow(page: page, home: home, isExpanded: expandedBinding(for: page))
                }
            }
            .padding(.vertical, 4)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            })
        }
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 1), Self.maxHeight))
    }

    private func expandedBinding(for page: HomePage) -> Binding<Bool> {
        Binding(
            get: { expandedNames.contains(page.name) },
            set: { expanded in
                var names = expandedNames
                if expanded { names.insert(page.name) } else { names.remove(page.name) }
                expandedRaw = names.sorted().joined(separator: "\n")
            })
    }

    private var expandedNames: Set<String> {
        Set(expandedRaw.split(separator: "\n").map(String.init))
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One page: its name and how many of its lights are on; expanded, its sections.
struct PageRow: View {
    let page: HomePage
    let home: HomeModel
    @Binding var isExpanded: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                    Text(page.name)
                        .lineLimit(1)
                    Spacer()
                    if !page.lights.isEmpty {
                        OnCountBadge(lights: page.lights)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(isHovered ? Color.primary.opacity(0.06) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(page.sections) { section in
                        SectionView(section: section, home: home)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

/// "2 / 5": lights on out of all lights on the page; "–" while unknown.
struct OnCountBadge: View {
    let lights: [LightItem]

    var body: some View {
        let known = lights.compactMap(\.displayedOn)
        let on = known.filter { $0 }.count
        Text(known.isEmpty ? "–" : "\(on) / \(lights.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(on > 0 ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(on > 0 ? Color.yellow.opacity(0.25) : Color.primary.opacity(0.06), in: Capsule())
    }
}

struct SectionView: View {
    let section: HomeSection
    let home: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = section.title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ForEach(section.rows) { row in
                switch row {
                case .light(let light):
                    LightRowView(light: light) { on in home.setLight(light, on: on) }
                case .cover(let cover):
                    CoverRowView(cover: cover) { command in home.perform(command, on: cover) }
                }
            }
        }
    }
}

/// A light: its icon, name, switch. Reading `light.displayedOn` subscribes the row to the CLU's reports.
struct LightRowView: View {
    let light: LightItem
    let setOn: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        let isOn = light.displayedOn
        HStack(spacing: 8) {
            Image(systemName: light.symbol(on: isOn == true))
                .foregroundStyle(isOn == true ? Color.yellow : Color.secondary)
                .frame(width: 16)
            Text(light.name)
                .lineLimit(1)
                .foregroundStyle(isOn == nil ? .secondary : .primary)
            Spacer()
            Toggle(light.name, isOn: Binding(get: { isOn ?? false }, set: setOn))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(isOn == nil)
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if let isOn { setOn(!isOn) }
        }
        .help(isOn == nil ? "Stan nieznany — czekam na CLU" : "")
    }
}

#Preview("Sekcje demo") {
    let home = try! DemoDriver.makeHome()
    VStack(alignment: .leading, spacing: 2) {
        ForEach(home.pages[0].sections) { section in
            SectionView(section: section, home: home)
        }
    }
    .frame(width: 320)
    .padding(.vertical, 8)
}

/// A shutter: its icon, name and state, the up / stop / down buttons; with
/// slats, a second row with the tilt slider opens on a click.
struct CoverRowView: View {
    let cover: CoverItem
    let perform: @MainActor @Sendable (CoverItem.Command) -> Void
    @State private var showsTilt = false
    /// The tilt while the slider is being dragged; sent when it is let go.
    @State private var tiltDraft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: cover.looksClosed ? "window.shade.closed" : "window.shade.open")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(cover.name)
                        .lineLimit(1)
                        .foregroundStyle(cover.position == nil ? .secondary : .primary)
                    Text(cover.stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 0) {
                    commandButton("chevron.up", "Podnieś", .open)
                    if cover.supportsStop {
                        commandButton("stop.fill", "Zatrzymaj", .stop)
                    }
                    commandButton("chevron.down", "Opuść", .close)
                }
                if cover.supportsTilt {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsTilt ? 90 : 0))
                        .frame(width: 10)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard cover.supportsTilt else { return }
                withAnimation(.easeInOut(duration: 0.15)) { showsTilt.toggle() }
            }

            if showsTilt && cover.supportsTilt {
                tiltRow
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
    }

    private func commandButton(_ symbol: String, _ help: String, _ command: CoverItem.Command) -> some View {
        Button {
            perform(command)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(cover.pending == command ? Color.accentColor : Color.primary)
        .help(help)
    }

    private var tiltRow: some View {
        let shown = tiltDraft ?? Double(cover.displayedTilt ?? 0)
        return HStack(spacing: 8) {
            Image(systemName: Int(shown) == 0 ? "blinds.horizontal.closed" : "blinds.horizontal.open")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("Lamele")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(get: { shown }, set: { tiltDraft = $0 }), in: 0...100, step: 5,
                   onEditingChanged: { editing in
                guard !editing, let draft = tiltDraft else { return }
                perform(.tilt(Int(draft)))
                tiltDraft = nil
            })
            .controlSize(.mini)
            .disabled(cover.tilt == nil)
            Text(cover.displayedTilt == nil && tiltDraft == nil ? "–" : "\(Int(shown)) %")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.top, 2)
        .help(cover.tilt == nil ? "Położenie lameli nieznane — czekam na CLU" : "")
    }
}
