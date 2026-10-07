# HydrationRoutineAssistant

An iOS 18+ SwiftUI app for recording water intake, setting daily goals,
reviewing history and managing water-break reminders.

Designed for desk-based workers who lose track of drinking during focused work.
The workflow is to choose a personal goal, record drinks and check remaining water
without repeatedly opening the app. This is a tracking tool, not medical advice.

## Setup

1. Open `HydrationRoutineAssistant.xcodeproj` in Xcode 26.6 and run the
   `HydrationRoutineAssistant` scheme.
2. For physical devices, select the same development team for the app,
   `HydrationWidgetExtension` and `HydrationNotificationContent`, and enable App Groups on all three.
3. Use App Group `group.com.mingchen.HydrationRoutineAssistant`. If changing it,
   update all three entitlements and `HydrationSharedContainer.identifier` together.

## Features

- **Five screens:** Today, History, Daily goal, Routine and Record water (a sheet).
- **WidgetKit extension:** small and medium widgets show saved progress, so a worker
  can check remaining water at a glance. Tapping opens Today.
- **Reminders:** choose times, intervals and weekdays in Routine, then enable and save.
- **Notification Content extension:** category `HYDRATION_WATER_BREAK` shows recorded
  water, goal, remaining amount and last drink during a water break.
  **Open today's water intake** returns to Today to record the drink.

## Architecture and storage

SwiftUI Views → `HydrationWorkspaceViewModel` → Use Cases → `HydrationRepository`
protocol → `CoreDataHydrationRepository` → Core Data.
Core operations are `LogWaterIntakeUseCase`, `UpdateDailyHydrationGoalUseCase` and
`FetchTodayHydrationProgressUseCase`; they enforce domain rules and return typed errors.

Core Data keeps personal records available offline without a cloud account. One
`HydrationGoalEntity` has many `WaterIntakeEntryEntity` records, queried by goal and day.
Routine preferences use UserDefaults. The main app publishes a read-only JSON snapshot
to the App Group for both extensions and requests WidgetKit reloads after relevant changes.
Extensions do not access the database; the custom notification view uses UIKit.

## Usage

1. Save today's goal and record water.
2. Add the **Daily water intake** widget; check its values and tap it to open Today.
3. In **Routine**, choose reminder times and weekdays, enable reminders and save.
   Allow notifications when prompted.
4. Expand a water-break notification to view saved progress. Tap
   **Open today's water intake** to return to Today and record a drink.

## Data and limits

- Core Data stores goals and drinks. Both extensions read a saved App Group
  snapshot without changing records; stale or unavailable progress shows guidance.
- Goals accept 500–5000 mL; individual drinks accept 1–1000 mL and cannot be future-dated.
- WidgetKit controls refresh timing, so updates may not appear immediately.
- Reminders cover the next 7 calendar days, up to 60 notifications. Open the app
  regularly to refill the queue. Times follow the device calendar and time zone.
- Reaching today's goal cancels today's remaining reminders. Saving a changed
  routine replaces its pending reminders; **Turn off reminders** cancels them.
- If permission is denied, enable notifications in Settings and return to the app.

## References

- [Apple Core Data](https://developer.apple.com/documentation/coredata)
- [Apple WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [Apple notification appearance](https://developer.apple.com/documentation/usernotificationsui/customizing-the-appearance-of-notifications)
