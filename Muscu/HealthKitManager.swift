//
//  HealthKitManager.swift
//  Muscu
//
//  Singleton manager for HealthKit (steps, sleep, DOB, weight).
//

import Foundation
import Combine
import HealthKit

@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()

    @Published var isAuthorized: Bool = false
    @Published var todaySteps: Int = 0
    @Published var lastNightSleepHours: Double = 0
    /// Âge calculé à partir de la date de naissance Santé (nil si non disponible).
    @Published var healthKitAge: Int?
    /// Dernier poids (kg) depuis Santé (nil si non disponible).
    @Published var healthKitWeight: Double?

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isAuthorized = false
            return
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
              let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let dateOfBirthType = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) else {
            isAuthorized = false
            return
        }

        let toRead: Set<HKObjectType> = [stepType, sleepType, bodyMassType, dateOfBirthType]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: toRead)
            let stepStatus = healthStore.authorizationStatus(for: stepType)
            isAuthorized = stepStatus == .sharingAuthorized || stepStatus == .sharingDenied
        } catch {
            print("HealthKit authorization error: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - Profile (DOB → age, bodyMass → weight)

    /// Récupère l’âge (depuis la date de naissance) et le dernier poids. Met à jour healthKitAge et healthKitWeight.
    func fetchProfileData() async {
        await fetchAgeFromDateOfBirth()
        await fetchMostRecentBodyMass()
    }

    private func fetchAgeFromDateOfBirth() async {
        guard let dobComponents = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: dobComponents) else {
            healthKitAge = nil
            return
        }
        let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        healthKitAge = max(0, age)
    }

    private func fetchMostRecentBodyMass() async {
        guard let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            healthKitWeight = nil
            return
        }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let query = HKSampleQuery(
            sampleType: bodyMassType,
            predicate: nil,
            limit: 1,
            sortDescriptors: sort
        ) { [weak self] _, samples, error in
            guard let manager = self, error == nil,
                  let sample = samples?.first as? HKQuantitySample else {
                let ref = self
                Task { @MainActor in ref?.healthKitWeight = nil }
                return
            }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            Task { @MainActor in
                manager.healthKitWeight = kg
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Steps

    func fetchTodaySteps() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, statistics, error in
            if let error = error {
                print("Error fetching steps: \(error.localizedDescription)")
                return
            }
            guard let manager = self else { return }
            let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            Task { @MainActor in
                manager.todaySteps = Int(steps)
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Sleep (simplifié)

    func fetchLastNightSleep() async {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }

        let calendar = Calendar.current
        let now = Date()
        // On part sur les 24 dernières heures pour simplifier
        guard let start = calendar.date(byAdding: .day, value: -1, to: now) else { return }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [weak self] _, samples, error in
            if let error = error {
                print("Error fetching sleep: \(error.localizedDescription)")
                return
            }
            guard let manager = self,
                  let samples = samples as? [HKCategorySample] else { return }

            let asleepSamples = samples.filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }

            let totalSeconds = asleepSamples.reduce(0.0) { partial, sample in
                partial + sample.endDate.timeIntervalSince(sample.startDate)
            }

            let hours = totalSeconds / 3600.0

            Task { @MainActor in
                manager.lastNightSleepHours = hours
            }
        }

        healthStore.execute(query)
    }
}
