

<img width="100" height="100" alt="image" src="https://github.com/user-attachments/assets/2f467c11-c746-4dfe-a861-a31bad1889ce" />

# Paltsuun

A macOS menu bar app that makes sure you never miss the start of a meeting.

A few minutes before a meeting starts, Paltsuun shows a floating countdown above all
other windows. When the countdown reaches zero, it opens the meeting link in your
default browser.

## Features

- **Floating countdown** above all windows, spaces and full-screen apps, with a
  *Join meeting* button. It changes from green to red as the meeting approaches.
- **Auto-join.** Opens the meeting link (Google Meet, Zoom, Teams or any URL) when the
  countdown ends.
- **Start sound** when a meeting starts.
- **Today's meetings at a glance.** When you come back to the computer after being away,
  and when Paltsuun starts, meetings already in progress (with a *Join meeting* button)
  and small countdowns to the rest of today's meetings are shown for a few seconds.
- **New meeting toast.** When a meeting is added to a synced calendar, or you're invited
  to one, a toast shows it briefly. A new repeating meeting is shown once.
- Toasts that disappear by themselves show the seconds left next to their close button.
- **Menu bar app** that lists upcoming meetings.
- **Quick events.** *New Quick Event…* in the menu bar menu adds a local meeting. Set
  when it starts with a slider (time from now) or by entering the time. Each updates the
  other.
- **Sync log** of each calendar sync and the meetings it added, changed or removed.
- **Calendar view** for adding and editing meetings.
- **Google Calendar sync.** Declined meetings never remind you.

## Settings

These settings are in *Settings…* in the menu bar menu, together with calendar accounts.
The *Test* button next to the sound plays the selected sound.

| Setting                               | Default      |
| ------------------------------------- | ------------ |
| Remind me                             | 5 min before |
| Open link when meeting starts         | On           |
| Sound when meeting starts             | Glass        |
| Show today's meetings when back after | 30 min       |
| Show today's meetings for             | 10 s         |
| Check calendars for changes every     | 2 min        |
| Start at login                        | Off          |

## Calendar providers

Paltsuun does not depend on a particular calendar service. Meetings come from one or
more providers that implement `CalendarProvider`
(`Paltsuun/Providers/CalendarProvider.swift`). Providers that also implement
`EditableCalendarProvider` can be edited in the calendar view. Meetings from other
providers are read-only.

`MeetingStore` fetches meetings from every provider once a minute. If a provider fails,
its last results are kept and an error banner appears in the calendar window.

`LocalCalendarProvider` stores meetings you add in the app, including quick events, as
JSON in the app's sandbox container:

```
~/Library/Containers/com.esamatti.Paltsuun/Data/Library/Application Support/Paltsuun/meetings.json
```

### Remote calendars

Remote calendar services implement `RemoteCalendarSource`, which handles signing in and
fetching events. Each source is wrapped in a `SyncedCalendarProvider`. This provider
keeps a read-only local copy of the remote events in `synced-<id>.json` in the same
folder, so meetings still remind you when you're offline.

`CalendarSync` syncs every connected source every few minutes (2 by default, see
*Check calendars for changes every*), when the calendar shows
a month outside the synced range, and when you choose *Sync Calendars Now* from the
menu bar or click the refresh button in the calendar window (⌘R). Each sync covers the
past week, the next 90 days and the month shown in the calendar. The remote calendar
is the source of truth: each sync replaces the local copies in that range, so events
changed or deleted remotely are changed or deleted locally.

Each sync reports the meetings it added, changed and removed. These are listed in the
sync log, opened with *Sync Log…* in the menu bar menu or *Show Log…* in Settings. The
log is kept in memory and holds the latest 500 syncs. An added meeting is *new* when it
falls in the range covered by the previous sync, so it was created after that sync.
Meetings that only came into range as it moved forward aren't new. New meetings that
haven't ended and aren't declined are shown in a toast for a few seconds. A repeating
meeting is shown once, as its next occurrence. Meetings already in the local copy when
Paltsuun starts don't count as new, but meetings created while Paltsuun wasn't running
do.

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
  Views/                   Month grid, day agenda, meeting editor, quick event,
                           menu bar, settings
```
