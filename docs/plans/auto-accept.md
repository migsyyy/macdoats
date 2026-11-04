# Plan v2: auto-accept, queue indicator, live Dota settings

v1 was **REJECTED 3/3** by the adversarial review: `_workspace/adversarial-reviews/2026-10-31-adv-review-auto-accept.md`.
v2 was re-checked (single judge, 2026-11-01): **APPROVED_WITH_CONDITIONS**. The conditions are folded in as
§8 below, which **overrides** earlier sections where they disagree. Evidence: traces in `_workspace/traces/`.

## Scope
1. **Settings:** read Dota's live convars (`machine_convars.vcfg`), not the 2015 `config.cfg`.
2. **Queue indicator:** while you're in the matchmaking queue, the menu-bar icon shows a spinning star on a green
   pill (requested 2026-10-31).
3. **Auto-accept next match:** one-shot. It presses Return once when the accept popup is up and Dota is in front.

Out of scope: screen reading; setting Steam launch options; GSI; macOS notifications; the badge overlay window. The
icon covers the "waiting" state, so the badge window is cut.

## 1. Live Dota settings (Engine.refreshExternalSettings)
- **File:** `~/Library/Application Support/Steam/userdata/<id>/570/local/cfg/machine_convars.vcfg`. Any account
  whose file has the key `true` counts.
- **Keys** (regex `"<key>"\s+"(true|1)"`):
  - `dota_mouse_window_lock`: Dota's own mouse lock. It replaces the dead `in_lock_mouse_to_window`. Fix the panel
    text and the README troubleshooting too, telling users to turn off *Lock mouse to window* in Dota's options, or
    to run `dota_mouse_window_lock 0`.
  - `dota_activate_window_on_match_found`: if `false`, warn in the auto-accept row that Dota won't come to the
    front, so auto-accept can't work.
- Drop the `config.cfg` read entirely. Note that Dota writes this file at shutdown, so a change made mid-session
  shows after Dota quits.

## 2. Log watcher (`Sources/DotaLog.swift`)
- **Path:** from `Steam/steamapps/libraryfolders.vdf`, take the library whose `"apps"` block lists `"570"`. The log
  is `<lib>/steamapps/common/dota 2 beta/game/dota/console.log`.
- **Always starts at the end** of the file (no replay), including after a reopen. If the queue was already running
  when MacDoats started, it isn't known; the indicator picks up at the next queue.
- **Event source:** `DispatchSource.makeFileSystemObjectSource` (`.extend/.write/.delete/.rename`). The file
  descriptor is closed **only in the source's cancel handler**. On `.delete/.rename` → cancel; `tick()` reopens
  when the path exists, at the end. If the file size shrinks below the offset (Dota rewrote it), read from 0.
- **Decoding:** split raw bytes on `\n`; keep partial lines in a `Data` buffer; decode each complete line with
  `String(decoding:as: UTF8.self)` (lossy, never nil).
- **Matching is anchored** to the timestamp prefix, so player text can't match. Each pattern must follow the
  `MM/DD HH:MM:SS ` prefix:

  | Pattern (after the timestamp) | Event |
  |---|---|
  | `[GCClient] Send msg 7033 (k_EMsgGCStartFindingMatch)` | `.queueStarted` (you queued: solo or leader) |
  | `[GCClient] Send msg 7036 (k_EMsgGCStopFindingMatch)` | `.queueStopped` (verified live 2026-11-01: start/cancel/start/cancel logs 7033/7036 pairs within ~1 s) |
  | `[SOCache] CGCSOCacheSubscribedJob(owner=<Lobby:<id>>)` | `.lobbyJoined(id)` |
  | `[SOCache] CGCSOCacheUnsubscribedJob(owner=<Lobby:<id>>)` | `.lobbyLeft(id)` |
  | `[GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus)` | `.readyUpStatus`: the accept popup is live |
  | `[GCClient] Send msg 7070 (k_EMsgGCReadyUp)` | `.answered` (accept **or** decline) |

## 3. State: deliberately small
```
inQueue: Bool          // set by .queueStarted; cleared by .queueStopped, .lobbyJoined, Dota quit
popupLobby: String?    // set by .lobbyJoined(id); cleared by .lobbyLeft(id) or .answered
answered: Set<String>  // lobby ids we've seen answered (by us or the user)
pressed: Set<String>   // lobby ids MacDoats already pressed Return for (max 1 per lobby)
```
- **Indicator:** queueing = `inQueue`. After a fall-through, Dota re-queues anyone who accepted. If the trace
  confirms a fresh `StartFindingMatch` or `RequestMMInfo` line logs then, the indicator resumes; if not, it stays
  off until the next queue start, which is the safe choice.
- **Accept trigger:** `.readyUpStatus` while `popupLobby == id`, `id ∉ answered`, and `id ∉ pressed`. This works
  for solo, leader and party member, because it needs no queue start. Bot and custom lobbies and reconnects have no
  ready-up, so they never trigger.

## 4. Auto-accept action
- **Setting:** `autoAcceptNext` (in memory, **not saved**, default off). Turn it on from the panel ("Auto-accept
  next match") or with ⌃⌥⌘A. It turns itself **off** after a press, and on `.queueStopped`.
- **Feedback:** while it's on, a small gold dot on the menu-bar icon. ⌃⌥⌘A plays a short sound (Tink on, Pop off),
  so you get feedback inside Dota too.
- **On trigger:**
  1. Abort unless every one of these holds at the instant of posting:
     - `autoAcceptNext`;
     - `trusted` (Accessibility granted);
     - **Dota is frontmost** (`NSWorkspace.frontmostApplication` bundle ID);
     - screen not locked (`CGSessionCopyCurrentDictionary` → `CGSSessionScreenIsLocked` absent or false).
  2. Wait 0.4 s, check every condition again, then post one Return down/up (`postKey`, synthetic tag).
  3. Insert the id into `pressed`, set `autoAcceptNext = false`, play the Glass sound.
- **No retry.** If Dota isn't in front at the trigger, MacDoats **never posts**. It plays the Basso sound and shows
  "Dota wasn't in front, accept it yourself" in the panel. Relies on Dota's own
  `dota_activate_window_on_match_found` (checked in §1). No `activate()` call, because macOS 14+ may refuse it.
- A **generation counter** is incremented on every arm/disarm and lobby change. The delayed post checks the
  generation, so a stale chain can't fire.

## 5. Queue indicator (menu-bar icon)
- **Look:** while queueing, the ⌘ sigil on the tome becomes a **4-point star of the same size**, on a **green
  pill** (Radiant green `#6CB33F`) instead of the cursor-lock red. It's still the template-style white glyph on
  the pill.
- **Motion:** the star turns **180° clockwise once every second**. It's an eased turn of about 0.35 s, then a hold;
  a ticking-clock feel. The star has 4-fold symmetry, so each turn ends on the same shape and the tick reads as
  motion, not drift.
  - **Assumption to confirm:** a continuous 180°/s spin is the alternative. It's a one-line change.
- **Rendering:**
  - Pre-render 12 frames covering 0–90°; the symmetry repeats beyond that.
  - Drive them with a `Timer` at about 30 fps **only during the 0.35 s turn**, then stop until the next second.
  - Idle cost is near zero, and nothing runs when you're not queued.
- **Priority:** queueing > cursor locked > Dota running > idle. While queued, it shows green even if the cursor
  lock is engaged; the lock shows again when the queue ends.
- `Icon.swift` gains `drawGlyph(sigil: .command | .star(angle))` and `MenuIcon.queue(frame:)`.
- `StatusItem` subscribes to `engine.$inQueue` alongside the existing CombineLatest.

## 6. Tests (must work in release builds)
- Replace `assert` in `--selftest` with a `check(_:_:)` helper that prints and `exit(1)`s.
- **Parser:**
  - real recorded lines → expected events;
  - a Steam name containing `k_EMsgGCReadyUp` → no event (anchored match);
  - BOM on the first line;
  - invalid UTF-8 byte → line still decoded.
- **Trigger:** feed the solo trace and the party trace (once recorded) → exactly one trigger per popup lobby.
  - **Bot or custom lobby** (no ready-up) → none.
  - **Popup the user already answered** → none.
- **Watcher:** append, truncate and replace a temp file → correct lines, no replay.
- **Icon:** `--screenshots` renders the queue icon (green pill, star at 0° and 45°) for visual check.
- **Manual:**
  - solo queue with auto-accept on while in another app; check Dota comes forward and Return accepts;
  - again with Dota's bring-to-front off → no keypress, Basso sound;
  - party member (once supported).

## 7. Docs and versioning
- **README:** auto-accept (one-shot, requires `-condebug`), the queue indicator, and ⌃⌥⌘A.
  - Troubleshooting uses `dota_mouse_window_lock`.
  - Correct the "doesn't read game files" claim: MacDoats reads `console.log` and `machine_convars.vcfg`.
  - Add `DotaLog.swift` to the source table.
- **Preview:** `Engine(preview:)` gets defaults for the new row, so `--screenshots` shows it. Regenerate the screenshots.
- **Version:** bump to 0.3.0.

## Evidence still needed (user is recording, 2026-10-31)
One `-condebug` session, as a **party member**, with:
- a match accepted;
- ideally a decline;
- a full game.

Copy `console.log` **before Dota is relaunched**, since it may be cleared on launch (unverified). From it, confirm:
1. **Members:** do they get `RequestMMInfo` and/or `ReadyUpStatus`? This decides the member queue indicator and
   confirms the trigger.
2. **Decline:** what does it log, and does `ReadyUpStatus` still arrive after it?
3. **Fall-through:** after one, is there a fresh queue-start line?
4. **Game:** what do game start and end log, and is any `ReadyUpStatus` sent outside the accept popup?
5. **Flushing:** check line timestamps against your notes. Does it write in real time, or in late bursts?

### Party trace results (recorded 2026-10-31 22:40 → 00:11, you as a party member)
1. **Members:** `ReadyUpStatus` arrives (10 lines, 23:22:38–42, sizes growing by 2 bytes per accept) and `ReadyUp`
   was sent when you accepted at 23:22:42. **The accept trigger works for members.**
   - `RequestMMInfo` (7681) is **not** a queue signal: it fires when you join a party (22:42:52, 23:00:03). Dropped.
   - The leader's queue start logs **nothing named** on a member's client. The only trace is an opaque
     `k_ESOMsg_UpdateMultiple` (397 bytes at 23:20:27). Sizes depend on party makeup, so no indicator for that case.
   - A member *can* send `StartFindingMatch` (yours at 23:19:45) and `StopFindingMatch` (23:20:19).
2. **Decline (recorded live 2026-11-01 00:21):** popup lobby at 00:21:54, `ReadyUpStatus` ×8 by 00:21:58, one
   more at 00:22:12 (the friend's decline), lobby unsubscribed 00:22:19. **No `ReadyUp` (7070) was sent from this
   client**, and **no fresh `StartFindingMatch` after the fall-through**, so `inQueue` stays off afterwards (the safe
   choice). Re-queue after a fall-through is a **Dota Plus** option; this account doesn't have it, so whether that
   re-queue logs `StartFindingMatch` is unknown. Either way the icon is only cosmetic; auto-accept doesn't need it. Earlier note: `ReadyUpStatus` continued once after your accept (23:22:42), so `answered` must
   gate it, as planned.
3. **Fall-through:** not recorded.
4. **Game:** `LOBBY STATE RUN … connecting to MatchID` at accept +1 s, then `DOTA_GAMERULES_STATE_*` lines. No
   `ReadyUpStatus` outside the popup in a 47-minute game. The lobby unsubscribed at game end (00:09:46).
   - A **spectate** (`SpectateFriendGame`, 22:59:29) also subscribes a Lobby and stays subscribed until the next
     one; it has no ready-up, so the ReadyUpStatus trigger correctly ignores it.
5. **Log file:** one `[CommandLine] … -condebug` header, first line 22:40:25: **rewritten on each launch**.
   Real-time flushing still unverified (read after quit); check with `tail -f` on the next queue.

Correction to 5: real-time flushing is now **verified** (lines on disk within ~1 s, 2026-11-01).

**Effect on the plan:** the indicator shows only for queues *you* start; for a leader-started queue the icon stays
put and auto-accept still fires. Remaining: one plan re-check (single judge), then build.

## 8. Re-check conditions (2026-11-01, override earlier sections)
1. **Arming lasts until a match starts, not until a press.** Disarm on `LOBBY STATE RUN: lobby <id>` for a lobby
   MacDoats pressed (the game is really starting), on Dota quit, or by hand. **Not** on `.queueStopped` and not
   on the press: you cancel and re-queue often, and a stranger's decline leads to a second popup. Every automatic
   disarm plays Pop.
   - Safety cap: also disarm after **60 min** armed, so a forgotten arming can't accept an hour later (party
     members never see the leader's cancel).
2. **Detect a missing `-condebug`.** The auto-accept row is enabled only if `console.log` exists and its first
   `[CommandLine]` line contains `-condebug`, and the file was created at or after Dota's process start
   (`sysctl` `kern.proc.pid` start time; `launchDate` is nil). Otherwise the row shows the launch-option steps.
3. **Post-time recheck includes the popup:** at post time also require `popupLobby == id` and `id ∉ answered`;
   `.answered` bumps the generation. No Return after you clicked Accept or Decline yourself.
4. **Retry within the popup, Basso once.** Every `ReadyUpStatus` for the live popup re-runs the trigger (8–10
   arrive per popup), so a late Space switch still gets one press. Basso plays at most once per lobby.
5. **Sleep:** while armed and Dota running, hold an `IOPMAssertionTypePreventUserIdleDisplaySleep` assertion;
   release on disarm. The panel row says "Keeps your display awake while armed".
6. **Tests:** fixtures are the GCClient/SOCache/LOBBY lines from `_workspace/traces/`, **with IDs rewritten**
   (account, lobby, party, SteamID64, names), embedded in the selftest. Add cases: answered within 0.4 s; abort then
   a later status; `lobbyLeft` for a different id; `.vcfg` parsing; the `-condebug` check.
7. **Patterns** are prefix matches after `MM/DD HH:MM:SS `; Subscribed lines end in ` [in cache]`, so never
   end-anchor. Tested against the verbatim trace lines.
8. **Smaller items:**
   - `AXIsProcessTrusted()` live at post time.
   - Glass only when our 7070 follows within 2 s; otherwise Basso.
   - On reopen, truncate or Dota quit, clear the line buffer and `popupLobby`, and bump the generation.
   - `.lobbyLeft` clears only a matching id. Deliver the source on `.main`.
   - `inQueue` also clears on Dota quit and after 60 min with no match.
   - The armed dot goes into all three icons as a non-template overlay.
   - `machine_convars.vcfg` is also written at launch, not only at shutdown.
9. **Never run MacDoats while you're playing.** Build only; run the selftest and screenshots when Dota is closed.
