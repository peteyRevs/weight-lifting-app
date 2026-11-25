#if canImport(HealthKit)
    import Foundation
    import HealthKit
    import LedgerDomain

    /// The three HealthKit types Ledger uses, in one place (F16): it writes workouts and active energy, and reads
    /// those and heart rate.
    enum HealthTypeSet {
        static let heartRate = HKQuantityType(.heartRate)
        static let activeEnergy = HKQuantityType(.activeEnergyBurned)
        static let share: Set<HKSampleType> = [.workoutType(), activeEnergy]
        static let read: Set<HKObjectType> = [.workoutType(), heartRate, activeEnergy]
    }

    /// The metadata keys a finished workout carries (F16): HealthKit's brand name, which the Health and Fitness
    /// apps show, and Ledger's own.
    enum HealthMetadataKey {
        static let brandName = HKMetadataKeyWorkoutBrandName
        static let workoutID = "com.petearevalo.Ledger.workoutID"
        static let totalVolumeGrams = "com.petearevalo.Ledger.totalVolumeGrams"
        static let program = "com.petearevalo.Ledger.program"
        static let day = "com.petearevalo.Ledger.day"

        /// The brand name from the app's Info.plist, `value` reading one of its keys: `CFBundleDisplayName`, else
        /// `CFBundleName`, a blank one counting as absent (as `AppAbout`'s name does), so no source names the
        /// product (`docs/product-decisions.md`, Naming).
        static func brandName(_ value: (String) -> Any?) -> String? {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = value(key) as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return name
                }
            }
            return nil
        }
    }

    extension HealthWorkoutMetadata {
        /// What a finished workout carries, by `HealthMetadataKey`: the volume as a mass in grams, and a name the
        /// workout has not is left out.
        func healthKitEntries(brandName: String?) -> [String: HealthMetadataValue] {
            var entries: [String: HealthMetadataValue] = [
                HealthMetadataKey.workoutID: .text(workoutID.rawValue.uuidString),
                HealthMetadataKey.totalVolumeGrams: .grams(totalVolumeGrams)
            ]
            entries[HealthMetadataKey.brandName] = brandName.map(HealthMetadataValue.text)
            entries[HealthMetadataKey.program] = programName.map(HealthMetadataValue.text)
            entries[HealthMetadataKey.day] = dayName.map(HealthMetadataValue.text)
            return entries
        }
    }

    extension HealthError {
        /// `error` as a `HealthError`: HealthKit's codes that the cases name, any other by its code alone, and never
        /// its text (criterion 14).
        init(_ error: any Error) {
            if let health = error as? HealthError {
                self = health
                return
            }
            let code = (error as NSError).code
            guard (error as NSError).domain == HKErrorDomain else {
                self = .underlying(code: code)
                return
            }
            switch HKError.Code(rawValue: code) {
            case .errorAnotherWorkoutSessionStarted: self = .anotherWorkoutSessionStarted
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined: self = .notAuthorized
            case .errorHealthDataUnavailable: self = .unavailable
            default: self = .underlying(code: code)
            }
        }
    }

    /// Authorization against HealthKit, for both apps: the watch's session provider uses it, and the phone's will
    /// (F16 S3).
    struct HealthKitAuthorizer: Sendable {
        let healthStore: HKHealthStore

        func authorization() -> HealthAuthorization {
            .workouts { healthStore.authorizationStatus(for: .workoutType()) }
        }

        /// Shows HealthKit's sheet for `HealthTypeSet` if the lifter has not answered it.
        func requestAuthorization() async throws -> HealthAuthorization {
            guard HKHealthStore.isHealthDataAvailable() else {
                throw HealthError.unavailable
            }
            do {
                try await healthStore.requestAuthorization(toShare: HealthTypeSet.share, read: HealthTypeSet.read)
            } catch {
                throw HealthError(error)
            }
            return authorization()
        }
    }
#endif
