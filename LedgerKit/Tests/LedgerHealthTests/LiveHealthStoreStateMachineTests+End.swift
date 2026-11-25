#if canImport(HealthKit)
    import Foundation
    import HealthKit
    import LedgerDomain
    import LedgerFakes
    @testable import LedgerHealth
    import Testing

    // Criteria 5, 6 and 9 (F16 S2b): the end's order and metadata, a discard, another app's workout.

    extension LiveHealthStoreStateMachineTests {
        @Test("The end stops the activity, and on .stopped ends the collection, adds metadata, finishes, ends")
        func endSession_orders_stop_endCollection_addMetadata_finish_end() async throws {
            let session = ScriptedSession(autoplay: false)
            let store = Self.store(ScriptedProvider(session: session))
            try await Self.start(store, on: session)
            let ending = Task { try await store.endSession(metadata: Self.metadata, at: Self.end) }
            await session.wait(for: "stopActivity")
            session.play(.state(.stopped, Self.end))
            let record = try await ending.value
            #expect(session.log.drop { $0 != "stopActivity" } == [
                "stopActivity", "→stopped", "endCollection", "addMetadata", "finishWorkout", "end"
            ])
            let workout = ScriptedSession.workout
            #expect(record.healthKitUUID == workout.uuid && record.start == workout.start && record.end == workout.end)
            #expect(record.avgHeartRate == 118 && record.maxHeartRate == 162 && record.activeEnergyKcal == 240)
            #expect(await Self.events(4, of: store).last == .ended(Self.end))
            await #expect(throws: HealthError.noActiveSession) {
                try await store.endSession(metadata: Self.metadata, at: Self.end)
            }
        }

        @Test("The workout carries the brand name and Ledger's four keys, exactly; the volume as grams")
        func metadataKeys_exact() async throws {
            let session = ScriptedSession()
            let store = Self.store(ScriptedProvider(session: session))
            try await store.startSession(workoutID: Self.workout, at: Self.start)
            _ = try await store.endSession(metadata: Self.metadata, at: Self.end)
            let metadata = try #require(session.metadata)
            #expect(Set(metadata.keys) == [
                HKMetadataKeyWorkoutBrandName, "com.petearevalo.Ledger.workoutID",
                "com.petearevalo.Ledger.totalVolumeGrams", "com.petearevalo.Ledger.program",
                "com.petearevalo.Ledger.day"
            ])
            #expect(metadata[HKMetadataKeyWorkoutBrandName] == .text("Ledger"))
            #expect(metadata["com.petearevalo.Ledger.workoutID"] == .text(Self.workout.rawValue.uuidString))
            #expect(metadata["com.petearevalo.Ledger.totalVolumeGrams"] == .grams(4_200_000))
            #expect(metadata["com.petearevalo.Ledger.program"] == .text("Strength"))
            #expect(metadata["com.petearevalo.Ledger.day"] == .text("Day A"))
            let bare = HealthWorkoutMetadata(
                workoutID: Self.workout, programName: nil, dayName: nil, totalVolume: .kilograms(0), doneSets: 0
            )
            #expect(Set(bare.healthKitEntries(brandName: nil).keys) == [
                "com.petearevalo.Ledger.workoutID", "com.petearevalo.Ledger.totalVolumeGrams"
            ])
        }

        @Test("The brand name is the bundle's display name, else its name; a blank one counts as absent")
        func brandName_fromTheBundle() {
            let lookup = { (plist: [String: String]) in HealthMetadataKey.brandName { plist[$0] } }
            #expect(lookup(["CFBundleDisplayName": "Ledger", "CFBundleName": "LedgerWatch"]) == "Ledger")
            #expect(lookup(["CFBundleDisplayName": "  ", "CFBundleName": "LedgerWatch"]) == "LedgerWatch")
            #expect(lookup([:]) == nil)
        }

        @Test("A discard ends the session and discards the workout: nothing is finished")
        func discardSession_writesNothing() async throws {
            let session = ScriptedSession()
            let store = Self.store(ScriptedProvider(session: session))
            await #expect(throws: HealthError.noActiveSession) { try await store.discardSession() }
            try await store.startSession(workoutID: Self.workout, at: Self.start)
            try await store.discardSession()
            #expect(session.log.suffix(2) == ["end", "discardWorkout"])
            #expect(!session.log.contains("finishWorkout"))
            #expect(await Self.events(4, of: store).last == .ended(Fixtures.now))
        }

        @Test("Another app's workout ends ours with its own event, and nothing is written")
        func anotherWorkoutSessionStarted_mapsToEvent_noSave() async throws {
            let session = ScriptedSession()
            let store = Self.store(ScriptedProvider(session: session))
            try await store.startSession(workoutID: Self.workout, at: Self.start)
            session.play(.failed(.anotherWorkoutSessionStarted))
            #expect(await Self.events(4, of: store).last == .anotherWorkoutSessionStarted)
            #expect(session.log.last == "discardWorkout")
            #expect(!session.log.contains("finishWorkout") && !session.log.contains("addMetadata"))
            await #expect(throws: HealthError.noActiveSession) {
                try await store.endSession(metadata: Self.metadata, at: Self.end)
            }
        }

        @Test("Another app's workout during the start fails the start with its own event")
        func anotherWorkoutSessionStarted_duringStart() async throws {
            let session = ScriptedSession(autoplay: false)
            let store = Self.store(ScriptedProvider(session: session))
            let starting = Task { try await store.startSession(workoutID: Self.workout, at: Self.start) }
            await session.wait(for: "prepare")
            session.play(.failed(.anotherWorkoutSessionStarted))
            await #expect(throws: HealthError.anotherWorkoutSessionStarted) { try await starting.value }
            #expect(await Self.events(1, of: store) == [.anotherWorkoutSessionStarted])
            #expect(!session.log.contains("startMirroring") && !session.log.contains("finishWorkout"))
        }
    }

    // Criterion 10 and the channel: recovery, data in and out; and HealthKit's vocabulary.

    extension LiveHealthStoreStateMachineTests {
        @Test("Recovery attaches the kept session again: its callbacks reach the store, and it ends as any other")
        func recovery_reattachesDelegates() async throws {
            let recovered = ScriptedSession()
            let store = Self.store(ScriptedProvider(recoverable: recovered))
            #expect(try await store.recoverActiveSession())
            #expect(try await !store.recoverActiveSession())
            #expect(await Self.events(1, of: store) == [.recovered])
            let heartRate = await store.heartRate()
            let samples = HealthStoreContractTests.samples([96, 101])
            samples.forEach { recovered.play(.heartRate($0)) }
            #expect(await HealthStoreContractTests.next(2, of: heartRate) == samples)
            let record = try await store.endSession(metadata: Self.metadata, at: Self.end)
            #expect(record.healthKitUUID == ScriptedSession.workout.uuid)
            #expect(recovered.log.last == "end")
            #expect(try await !Self.store(ScriptedProvider()).recoverActiveSession())
        }

        @Test("What the phone sends arrives in batches; a send goes over the session, and needs one")
        func channel_overThePrimarySession() async throws {
            let session = ScriptedSession()
            let store = Self.store(ScriptedProvider(session: session))
            await #expect(throws: HealthError.noActiveSession) { try await store.remoteChannel.send(Data([1])) }
            try await store.startSession(workoutID: Self.workout, at: Self.start)
            try await store.remoteChannel.send(Data([1, 2]))
            session.play(.received([Data([3])]))
            #expect(await HealthStoreContractTests.next(1, of: store.remoteChannel.incoming) == [[Data([3])]])
            #expect(session.log.contains("send 2"))
        }

        @Test("HealthKit's errors map to the cases that name them, any other by its code")
        func healthError_fromHealthKit() {
            let error = { (code: HKError.Code) in NSError(domain: HKErrorDomain, code: code.rawValue) }
            #expect(HealthError(error(.errorAnotherWorkoutSessionStarted)) == .anotherWorkoutSessionStarted)
            #expect(HealthError(error(.errorAuthorizationDenied)) == .notAuthorized)
            #expect(HealthError(error(.errorHealthDataUnavailable)) == .unavailable)
            let invalid = HKError.Code.errorInvalidArgument.rawValue
            #expect(HealthError(error(.errorInvalidArgument)) == .underlying(code: invalid))
            #expect(HealthError(NSError(domain: "other", code: 7)) == .underlying(code: 7))
            #expect(HealthError(HealthError.mirroringTimedOut) == .mirroringTimedOut)
        }

        @Test("Ledger shares workouts and energy, and reads those and heart rate")
        func healthTypeSet() {
            #expect(HealthTypeSet.share == [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)])
            #expect(HealthTypeSet.read == [
                HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)
            ])
        }

        @Test("A HealthKit call returns its value, and fails as a HealthError")
        func healthKitCall_mapsFailures() async throws {
            #expect(try await healthKitCall { 7 } == 7)
            await #expect(throws: HealthError.unavailable) {
                try await healthKitCall {
                    throw NSError(domain: HKErrorDomain, code: HKError.Code.errorHealthDataUnavailable.rawValue)
                }
            }
        }
    }
#endif
