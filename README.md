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

## Water-break reminders

In **Routine**, choose reminder times, an interval and weekdays, enable the routine,
then save. The app asks for notification permission only for this explicit action.
If permission is denied, the preferences remain saved and the page offers a link
to notification settings. Allow notifications there and return to the app to apply them.

The app schedules the earliest 60 future reminders over 7 calendar days, excluding
the end of the selected window and any times that have already passed. Open the app
regularly to refill this bounded queue. It is not an indefinite background schedule.
Dates follow the device's calendar and time zone; nonexistent daylight-saving times
are skipped and a repeated wall-clock time is scheduled only once.

Reaching today's goal cancels the rest of today's reminders while retaining future
routine days. Saving a changed routine replaces its previous pending reminders;
**Turn off reminders** cancels them without requesting notification permission.
Other notification categories are not cancelled.

After permission is granted, **Send test reminder** schedules a notification in
5 seconds. It appears while the app is open as well as in the background. Tapping
the reminder or its **Open today's water intake** action opens Today.
The `HYDRATION_WATER_BREAK` category prepares integration with the custom
Notification Content Extension, which is added in a separate update.

On 7 October 2026, an iPhone 17 Pro Simulator running iOS 26.5 verified permission
refusal and recovery after enabling notifications, foreground and background test
delivery, tapping a notification to open Today, changed-interval replacement,
goal-completion cancellation for today only, and stopping reminders across relaunch.
The notification-settings link opened the Settings home page in that run; navigating
through **Settings > Apps > HydrationRoutineAssistant > Notifications** enabled
notifications. Direct settings navigation and delivery on a physical device remain
unverified. The QA routine was left off after these checks.

Automated tests use isolated mock schedulers and preference stores; they do not
grant system permission. Implementation references:
[Apple's local notification guide](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).
