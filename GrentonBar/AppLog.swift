import OSLog

enum AppLog {
    static let grenton = Logger(subsystem: "com.osieckiadam.GrentonBar", category: "grenton")
    static let app = Logger(subsystem: "com.osieckiadam.GrentonBar", category: "app")
}
