#if DEBUG
    import Dependencies
    import LedgerDesign
    import LedgerHealth
    import LedgerPersistence

    extension AppComposition {
        /// What Debug's Diagnostics page shows (F07 criterion 7): the database file, this device, Health's
        /// authorization, launch-to-first-frame (product decision #30), swift-dependencies' context and each table's
        /// row count. It reads the composition's own stores, never a store key or `deviceID`, so nothing is read
        /// before the database is open and a later recovery (#29) can still bind every key (S2-N2). `health` defaults
        /// to what HealthKit reports, which a package test host cannot ask.
        func diagnostics(health: HealthAuthorization = .workouts()) async -> [DiagnosticsSection] {
            @Dependency(\.context) var context
            var database: DatabaseDiagnostics?
            var failure: String?
            do {
                database = try await stores?.diagnostics()
            } catch {
                failure = String(describing: error)
            }
            return [
                DiagnosticsSection("App", lines: [
                    DiagnosticsLine("Database", database?.path ?? failure ?? "Not open", key: "path"),
                    DiagnosticsLine("Device", database?.deviceID.rawValue.uuidString ?? "Unknown", key: "deviceID"),
                    DiagnosticsLine("Health", health.rawValue, key: "health"),
                    DiagnosticsLine(
                        "Launch to first frame",
                        DiagnosticsLine.milliseconds(launchToFirstFrame),
                        key: "launch"
                    ),
                    DiagnosticsLine("Dependencies", "\(context)", key: "context")
                ]),
                DiagnosticsSection("Rows", lines: (database?.tables ?? []).map {
                    DiagnosticsLine($0.name, String($0.rows), key: "rows.\($0.name)")
                })
            ]
        }
    }
#endif
