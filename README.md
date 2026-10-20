

<img width="100" height="100" alt="image" src="https://github.com/user-attachments/assets/2f467c11-c746-4dfe-a861-a31bad1889ce" />

# Paltsuun

A macOS menu bar app that makes sure you never miss the start of a meeting.

A few minutes before a meeting starts, Paltsuun shows a floating countdown above all
other windows. When the countdown reaches zero, it opens the meeting link in your
default browser.

## Features

- **Floating countdown.** Shows a large countdown with the meeting name and a
  *Join meeting* button. It stays on top of all windows, spaces and full-screen apps.
  Each meeting gets its own countdown. Countdowns that are on screen at the same time
  are placed below or beside each other in start order, so they don't overlap. You can
  drag a countdown anywhere, and new countdowns appear where you last dragged one. The
  small ✕ button dismisses a countdown, and its link then isn't opened automatically.
- **Show a countdown early.** Choose *Show Next Countdown* (⌘S) from the menu bar menu,
  or right-click a meeting in the calendar and choose *Show Countdown*, to show its
  countdown right away instead of waiting for the reminder time. This also brings back
  a countdown you dismissed.
- **Urgency colors.** The countdown starts green and turns amber, orange and finally
  red as the start time approaches. It flashes during the last 10 seconds.
- **Auto-join.** When the countdown ends, the meeting link (Google Meet, Zoom, Teams,
  or any URL) opens automatically.
- **Start sound.** A sound plays when a meeting starts. You can pick the sound, or turn
  it off, in *Settings…*.
- **Lives in the menu bar.** Paltsuun starts hidden in the menu bar. If Google Calendar
  credentials haven't been entered yet, it opens *Settings* instead. The menu
  bar icon lists upcoming meetings and shows the remaining time while a countdown is
  running. Closing or minimizing the calendar window hides the app from the Dock.
- **Calendar view.** A month view for adding, editing and deleting meetings.
  Double-click a day to add a meeting, click a meeting to edit it, or right-click it
  for more actions.
- **Google Calendar.** Syncs your primary Google Calendar every 15 minutes. Meetings
  you have declined are shown crossed out and never remind you.
- **Start at login.** Optionally start Paltsuun when you log in.

## Settings

These settings are in *Settings…* in the menu bar menu, together with calendar accounts.
The *Test* button next to the sound plays the selected sound.

| Setting                       | Default      |
| ----------------------------- | ------------ |
| Remind me                     | 5 min before |
| Open link when meeting starts | On           |
| Sound when meeting starts     | Glass        |
| Start at login                | Off          |

## Calendar providers

Paltsuun does not depend on a particular calendar service. Meetings come from one or
more providers that implement `CalendarProvider`
(`Paltsuun/Providers/CalendarProvider.swift`). Providers that also implement
`EditableCalendarProvider` can be edited in the calendar view. Meetings from other
providers are read-only.

`MeetingStore` fetches meetings from every provider once a minute. If a provider fails,
its last results are kept and an error banner appears in the calendar window.

`LocalCalendarProvider` stores meetings you add in the app as JSON in the app's
sandbox container:

```
~/Library/Containers/com.esamatti.Paltsuun/Data/Library/Application Support/Paltsuun/meetings.json
```

### Remote calendars

Remote calendar services implement `RemoteCalendarSource`, which handles signing in and
fetching events. Each source is wrapped in a `SyncedCalendarProvider`. This provider
keeps a read-only local copy of the remote events in `synced-<id>.json` in the same
folder, so meetings still remind you when you're offline.

`CalendarSync` syncs every connected source every 15 minutes, when the calendar shows
a month outside the synced range, and when you choose *Sync Calendars Now* from the
menu bar or click the refresh button in the calendar window (⌘R). Each sync covers the
past week, the next 90 days and the month shown in the calendar. The remote calendar
is the source of truth: each sync replaces the local copies in that range, so events
changed or deleted remotely are changed or deleted locally.

To add another service, such as Outlook, implement `RemoteCalendarSource`, add a
`SyncedCalendarProvider` for it in `AppDelegate.swift`, and add its setup fields to
`SettingsView.swift`.

### Google Calendar

`GoogleCalendarSource` reads your primary calendar through the Google Calendar API.

- The Google Meet link (or another video conference link) is used as the meeting link.
- Events you have declined are marked as declined and never remind you.
- All-day events, cancelled events, and out of office, focus time and working location
  entries are skipped.

Sign-in uses the OAuth 2.0 flow for desktop apps. The consent page opens in your
browser and redirects back to a temporary local address (`http://127.0.0.1:<port>`)
that Paltsuun listens on. The refresh token is stored in the keychain.

Paltsuun doesn't include its own OAuth client, so you need to create one:

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project.
2. Enable the **Google Calendar API**.
3. Configure the OAuth consent screen. Add the
   `https://www.googleapis.com/auth/calendar.events.readonly` scope and add your
   account as a test user.
4. Under *Credentials*, create an **OAuth client ID** of type **Desktop app**.
5. In Paltsuun, open *Settings…* from the menu bar menu. Enter the client ID and client
   secret, then click *Connect…*.

While the app's publishing status is *Testing*, Google expires refresh tokens after
7 days and you have to connect again. To avoid this, set the publishing status to
*In production*. You don't need to verify the app to use it with your own account.

## Building

Requires Xcode 26.5 and macOS 26.5 or later.

Open `Paltsuun.xcodeproj` in Xcode and run the *Paltsuun* scheme, or build from the
command line:

```sh
xcodebuild -project Paltsuun.xcodeproj -scheme Paltsuun build
```

To build a Release version and install it to `/Applications`, run:

```sh
./install.sh
```

If Paltsuun is running, the script quits it before replacing it and opens the new
version afterwards.

## Project layout

```
Paltsuun/
  PaltsuunApp.swift        App entry: calendar window and menu bar extra
  AppDelegate.swift        Owns the store and reminders, Dock icon handling
  ContentView.swift        Calendar window
  Models/                  Meeting, MeetingStore, CalendarSync, settings, launch at login
  Providers/               CalendarProvider protocols, local and synced providers
    Google/                Google Calendar source
    OAuth/                 Loopback redirect receiver, PKCE, keychain
  Reminder/                Countdown logic, floating panel and its view
  Views/                   Month grid, day agenda, meeting editor, menu bar, settings
```
