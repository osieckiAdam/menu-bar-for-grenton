import OSLog

enum AppLog {
    static let grenton = Logger(subsystem: "com.osieckiadam.MenuBarForGrenton", category: "grenton")
    static let app = Logger(subsystem: "com.osieckiadam.MenuBarForGrenton", category: "app")
}
