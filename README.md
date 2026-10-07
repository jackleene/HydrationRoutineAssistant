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
The `HydrationWidgetExtension` reads this snapshot without opening Core Data.
Its small widget shows the recorded amount, goal and remaining water; the medium
widget adds a progress gauge and the last drinking time. Both open Today when tapped.
Changed progress requests a WidgetKit timeline reload after the snapshot is saved.
Refreshes that only change the snapshot timestamp do not spend another reload request.
A prebuilt midnight entry clears yesterday's total while waiting for fresh progress.

## Add and check the widget

1. Run the `HydrationRoutineAssistant` scheme in an iOS 18+ Simulator and open the app once.
2. Save today's goal and record a drink.
3. Edit the Home Screen, choose Add Widget, and search for HydrationRoutineAssistant.
4. Add the small or medium **Daily water intake** widget.
5. Record another drink or edit today's goal, return to the Home Screen, and compare the widget with Today.
6. Tap either widget to open Today, including when the app is not running.

WidgetKit controls when a reload request is rendered; a request is not a guarantee
of an instantaneous update. See [Apple's widget refresh guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

For device builds, select your own development team in Xcode and configure the
matching App Group for each target that shares this data. The app's entitlements
file is already linked in both Debug and Release. Simulator verification does not
validate device provisioning. See [Apple's App Group setup guide](https://developer.apple.com/documentation/xcode/configuring-app-groups).
