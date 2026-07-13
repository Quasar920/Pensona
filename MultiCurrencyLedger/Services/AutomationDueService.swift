import Foundation
import SwiftData

struct AutomationDueReport {
    let recurringTransactionCount: Int
    let installmentTransactionCount: Int
    let failures: [String]
}

/// Performs the same idempotent scan used by the management screens when the
/// app opens. One broken rule is isolated so it cannot block other due entries.
@MainActor
struct AutomationDueService {
    let context: ModelContext

    func generateAllDue(through date: Date = .now) -> AutomationDueReport {
        var recurringCount = 0
        var installmentCount = 0
        var failures: [String] = []

        let schedules = (try? context.fetch(FetchDescriptor<RecurringSchedule>())) ?? []
        for schedule in schedules where !schedule.isArchived && !schedule.isPaused {
            do {
                recurringCount += try RecurringScheduleService(context: context)
                    .generateDue(for: schedule, through: date).count
            } catch {
                failures.append("\(schedule.name)：\(error.localizedDescription)")
            }
        }

        let plans = (try? context.fetch(FetchDescriptor<InstallmentPlan>())) ?? []
        for plan in plans where !plan.isArchived && !plan.isPaused && !plan.isCompleted {
            do {
                installmentCount += try InstallmentPlanService(context: context)
                    .generateDue(for: plan, through: date).count
            } catch {
                failures.append("\(plan.name)：\(error.localizedDescription)")
            }
        }

        return AutomationDueReport(
            recurringTransactionCount: recurringCount,
            installmentTransactionCount: installmentCount,
            failures: failures
        )
    }
}
