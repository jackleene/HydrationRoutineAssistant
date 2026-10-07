# HydrationRoutineAssistant

## Shared hydration progress

App Group identifier: `group.com.mingchen.HydrationRoutineAssistant`.

The app keeps Core Data as the source of truth and publishes a small, versioned
`HydrationWidgetSnapshot.json` in the App Group container. The snapshot contains
the daily goal, consumed amount, last drinking time and calendar-day boundaries.
Atomic replacement prevents an extension from reading a partially written file.
Snapshots from another day or time zone must not be displayed as today's progress.

Saving a drink, changing a goal or refreshing Today updates the shared snapshot.
A sharing failure does not undo a saved drinking record; Today provides a retry.
This prepares shared data for the WidgetKit extension, which is implemented separately.

For device builds, select your own development team in Xcode and configure the
matching App Group for each target that shares this data. The app's entitlements
file is already linked in both Debug and Release. Simulator verification does not
validate device provisioning. See [Apple's App Group setup guide](https://developer.apple.com/documentation/xcode/configuring-app-groups).
