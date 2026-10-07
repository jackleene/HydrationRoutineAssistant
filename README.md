# HydrationRoutineAssistant

An iOS 18+ SwiftUI app for recording water intake, setting daily goals,
reviewing history and managing water-break reminders.

## Setup

1. Open `HydrationRoutineAssistant.xcodeproj` and run the
   `HydrationRoutineAssistant` scheme.
2. For physical devices, select your development team and configure
   `group.com.mingchen.HydrationRoutineAssistant` for the app and both extensions.

## Features

- **Today, History, Goal and Routine:** record drinks and manage daily hydration.
- **Widgets:** small and medium widgets show saved progress and open Today.
- **Reminders:** choose times, intervals and weekdays in Routine, then enable and save.
- **Custom notifications:** expanded reminders show recorded water, goal,
  remaining amount and last drink. **Open today's water intake** opens Today.

## Quick check

1. Save today's goal and record water.
2. Add the **Daily water intake** widget; check its values and tap it to open Today.
3. Allow notifications and use **Routine > Send test reminder**; delivery takes 5 seconds.
4. Hold the top banner for about two seconds. On the tested Simulator, notification
   center long-press did not work: open the group, swipe left on one reminder and
   select **View**, not **Open**.
5. Compare the custom view with Today, then tap **Open today's water intake**.

## Data and limits

- Core Data stores goals and drinks. Both extensions read a saved App Group
  snapshot without changing records; stale or unavailable progress shows guidance.
- WidgetKit controls refresh timing, so updates may not appear immediately.
- Reminders cover the next 7 calendar days, up to 60 notifications. Open the app
  regularly to refill the queue. Times follow the device calendar and time zone.
- Reaching today's goal cancels today's remaining reminders. Saving a changed
  routine replaces its pending reminders; **Turn off reminders** cancels them.
- If permission is denied, enable notifications in Settings and return to the app.

## Verification

Simulator checks on 7 October 2026 covered widget updates/navigation, reminder
permissions/replacement/cancellation, and custom notification display/action forwarding.
Manual checks also covered rejected water/goal inputs and history without a saved goal.
Unit tests cover reminder boundaries, permission and failure handling, and notification states.
Workflow integration tests use isolated SQLite, preferences and shared files with a mock
reminder scheduler; they do not send system notifications.
Custom notifications were also checked in dark mode and at the largest accessibility text size.
Physical-device signing and delivery remain unverified.

The dedicated QA Simulator uses **Persistent** banners for manual testing;
restore **Temporary** after QA. Run the main scheme's tests in Xcode with **Command-U**.
