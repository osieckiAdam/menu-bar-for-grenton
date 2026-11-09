import Foundation
import GrentonKit

/// A page of the mobile interface (usually a room) with the devices the menu shows.
struct HomePage: Identifiable {
    /// The page's position in the interface.
    let id: Int
    let name: String
    let sections: [HomeSection]

    var rows: [HomeRow] { sections.flatMap(\.rows) }
    var lights: [LightItem] { sections.flatMap(\.lights) }
    var covers: [CoverItem] { sections.flatMap(\.covers) }
}

/// The rows between one section header and the next. Rows above the
/// first header (or on a page without headers) form a section without a title.
struct HomeSection: Identifiable {
    let id: String
    let title: String?
    let rows: [HomeRow]

    var lights: [LightItem] { rows.compactMap { if case .light(let light) = $0 { light } else { nil } } }
    var covers: [CoverItem] { rows.compactMap { if case .cover(let cover) = $0 { cover } else { nil } } }
}

/// One row of the menu: a light or a shutter.
enum HomeRow: Identifiable {
    case light(LightItem)
    case cover(CoverItem)

    /// A row for `entity`, or `nil` when the menu does not show it.
    @MainActor
    init?(_ entity: BoundEntity) {
        if let light = LightItem(entity) {
            self = .light(light)
        } else if let cover = CoverItem(entity) {
            self = .cover(cover)
        } else {
            return nil
        }
    }

    var id: String {
        switch self {
        case .light(let light): light.id
        case .cover(let cover): cover.id
        }
    }
}

/// Builds the menu's tree from the devices: page → section header → rows in widget order.
@MainActor
enum HomeListBuilder {
    /// The pages that have at least one row.
    ///
    /// Pages and sections come from each device's descriptor, in the
    /// order the system lists devices (page order). When no device in the
    /// interface sits under a header, every page is one section and a
    /// device shown twice on a page (the same CLU object) appears once.
    static func pages(devices: [BoundDevice], physicalObjects: [PhysicalObject]) -> [HomePage] {
        var pages: [(page: DevicePage, devices: [BoundDevice])] = []
        for device in devices {
            if let index = pages.firstIndex(where: { $0.page.index == device.descriptor.page.index }) {
                pages[index].devices.append(device)
            } else {
                pages.append((device.descriptor.page, [device]))
            }
        }
        let hasHeaders = devices.contains { $0.descriptor.section != nil }
        return pages
            .sorted { $0.page.index < $1.page.index }
            .map { hasHeaders ? sectionedPage($0.page, $0.devices) : flatPage($0.page, $0.devices, physicalObjects) }
            .filter { !$0.sections.isEmpty }
    }

    private static func sectionedPage(_ page: DevicePage, _ devices: [BoundDevice]) -> HomePage {
        var sections: [HomeSection] = []
        var current = (id: "\(page.index)-top", section: DeviceSection?.none, rows: [HomeRow]())
        func close() {
            if !current.rows.isEmpty {
                sections.append(HomeSection(id: current.id, title: current.section?.title, rows: current.rows))
            }
        }
        for device in devices {
            if device.descriptor.section != current.section {
                close()
                let section = device.descriptor.section
                current = (section.map { "\(page.index)-\($0.id)" } ?? "\(page.index)-top", section, [])
            }
            current.rows += device.entities.compactMap(HomeRow.init)
        }
        close()
        return HomePage(id: page.index, name: page.name, sections: sections)
    }

    private static func flatPage(_ page: DevicePage, _ devices: [BoundDevice], _ physicalObjects: [PhysicalObject]) -> HomePage {
        var objectOfEntity: [String: ObjectKey] = [:]
        for object in physicalObjects {
            for widget in object.widgets {
                for entityId in widget.entityIds { objectOfEntity[entityId] = object.key }
            }
        }
        var seen: Set<ObjectKey> = []
        let rows = devices.flatMap { $0.entities.compactMap(HomeRow.init) }.filter { row in
            guard let key = objectOfEntity[row.id] else { return true }
            return seen.insert(key).inserted
        }
        let sections = rows.isEmpty ? [] : [HomeSection(id: "\(page.index)-top", title: nil, rows: rows)]
        return HomePage(id: page.index, name: page.name, sections: sections)
    }
}
