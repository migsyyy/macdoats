# Research spike: auto-accept a found match

2026-10-31. Goal: accept a found Dota 2 match by sending one keystroke, relying on Dota's own
"bring to front" behaviour instead of screen reading.

## Findings

### 1. Dota brings itself to the front: two client convars
Both were confirmed in the Mac client (`game/dota/bin/osx64/libclient.dylib`), with these descriptions:

| Convar | Description in the binary | Options UI |
|---|---|---|
| `dota_activate_window_on_match_found` | "If set, brings Dota to the foreground when match found" | Options → Advanced → Game → *Bring Dota to foreground on match found* |
| `dota_activate_window_on_ready_check` | "If set, brings Dota to the foreground on a ready check" | *… for ready checks* |
| `dota_activate_window_on_hero_picking_start` | (pick phase / game start) | *… for pick phase and game start* |
| `dota_activate_window_on_unpause` | (unpause) | *… when unpaused* |

**Where it's stored:** `~/Library/Application Support/Steam/userdata/<steamid>/570/remote/cfg/config.cfg`. That is
the same file MacDoats already reads for `in_lock_mouse_to_window`.
- Dota writes only non-default values.
- On this Mac none of the four appear, so all are at their default. The user sees Dota take focus on a
  match, so the default is **on**.
- A line like `dota_activate_window_on_match_found "0"` in that file means the user turned it off.

**Known limit:** one user reports it doesn't fire while tabbed into the Steam overlay.

### 2. Accepting: Enter on the accept popup
- There's **no console command** to accept a match. The client has the popup class
  `CDOTA_DB_Popup_AcceptMatch` and the label token `#dota_accept_match_accept`, but no accept convar or
  command. `askconnect_accept` (bound to F3 in this config) isn't in the current binaries; it's probably a
  leftover.
- Three tools accept with the keyboard: bring Dota to the front, then press **Return**. Others click the
  Accept button they find on screen ([Eberer/Dota2GameAccepter_python](https://github.com/Eberer/Dota2GameAccepter_python),
  [MOBAGameAccepter](https://github.com/shkippppper/MOBAGameAccepter_python), "DOTA 2 Accepter" for AHK). None of these
  are for macOS, and none were checked against the current client. **Return accepting on the Mac client: verified by hand on
  2026-10-31. Pressing Return on the accept popup accepts the match.** The three Return-based tools:
  - [pawelma/dota2_automation](https://github.com/pawelma/dota2_automation) (Linux): "activates dota2 window and
    clicks enter to accept game". Its README warns not to Shift+Tab, which breaks it.
  - [xfalcox's gist](https://gist.github.com/xfalcox/4ad386fd8b405eecabbb) (Linux): `wmctrl -a Dota`, then
    Return ×3.
  - [etofok/Dota-2-Queue-and-Go](https://github.com/etofok/Dota-2-Queue-and-Go) (Windows AHK): requires the three
    *Bring Dota to foreground* options, then "will press Enter once".
- The Linux tools detect the match from Dota's "Matchmaking Status" desktop notification. On macOS, reading
  another app's notifications needs Full Disk Access, so that route is out.

### 3. Detecting "match found" from MacDoats without reading pixels
**Recommended: watch for Dota activating itself.** MacDoats already gets
`NSWorkspace.didActivateApplication` and sees every input event through its tap.
- If Dota becomes frontmost with **no user click or keypress in the last ~300 ms**, Dota activated itself.
  That means a match was found or a ready check started (or pick phase started, if that option is on).
- Then wait ~0.8 s. A fullscreen Dota sits in its own Space, so the switch animates.
- Then post Return down/up, tagged as synthetic like the Alt-Tab events.

## Risks and gaps

| Risk | Mitigation |
|---|---|
| Dota already frontmost when the match pops: no activation event | The user is at the screen and can press Enter. Auto-accept is for when you're away from Dota (brb mode). |
| Pick-phase activation also fires: Enter would open chat | Disarm after one accept. Re-arm only on an explicit toggle, or use GSI to tell queue from game (below). |
| Someone declines and you're re-queued | Allow up to N accepts per arming (planned "retries"). |
| Option turned off | Detect `"0"` in `config.cfg` and warn, as with `in_lock_mouse_to_window`. The console fix is `dota_activate_window_on_match_found 1`. |
| Steam overlay open | Document it; there's nothing to do from outside. |
| Valve's stance | Same input-level method as the AHK/Linux tools; it doesn't touch memory or game files. No Valve statement found either way. |

Possible test hook: the client also has `dota_fake_accept_state` / `dota_fake_accept_deny_count` (next to
the popup code). These may show the accept popup without queueing, but may need `sv_cheats`. **Unverified.**

## Proposed MacDoats feature (not built)
1. A toggle: **Auto-accept next match**. Off by default, and turns itself off after accepting (optionally after N re-queues).
2. Precheck: warn if `config.cfg` sets `dota_activate_window_on_match_found "0"`.
3. Trigger: Dota self-activation (no user input in the previous ~300 ms) → wait 0.8 s → Return.
4. A macOS notification: "Match accepted".
5. Later: a Game State Integration (GSI) listener (a cfg file in `game/dota/cfg/gamestate_integration/` plus a local HTTP
   endpoint), to disarm when hero selection starts and avoid the pick-phase Enter.

## Update: the console log tracks the queue (verified 2026-10-31)

With `-condebug` in Steam's launch options, Dota writes `game/dota/console.log`. It's rewritten each
launch, about 50 KB per short session. Dota logs every Game Coordinator message by name. One real queue
cycle on this Mac:

| Log line | Meaning |
|---|---|
| `[GCClient] Send msg 7033 (k_EMsgGCStartFindingMatch)` | Queue started |
| `[SOCache] CGCSOCacheSubscribedJob(owner=<Lobby:…>)` while queued | Match found (accept popup up) |
| `[GCClient] Recv msg 7170 (k_EMsgGCReadyUpStatus)` (repeating) | Accept counter ticking |
| `[GCClient] Send msg 7070 (k_EMsgGCReadyUp)` | You accepted |
| `[SOCache] CGCSOCacheUnsubscribedJob(owner=<Lobby:…>)` | Match fell through (someone didn't accept) |
| `[GCClient] Sending k_EMsgGCStopFindingMatch to GC` | Queue cancelled |
| `ChangeGameUIState: … -> …` | UI state changes (dashboard, loading…). Likely marks game start; not yet seen for a real game |

This replaces the "Dota activated itself" heuristic:
- MacDoats can follow the file with a kqueue file watcher (`DispatchSource`): no polling, no screen reading,
  negligible CPU.
- It knows when you're queued, when a match pops, whether *you* accepted, and when a match falls through.
  That makes retries reliable, and it works even when Dota is already in front.
- On "match found", MacDoats can bring Dota to the front itself, so it no longer depends on
  `dota_activate_window_on_match_found`.

**Costs:**
- The user must add `-condebug` once. MacDoats can't safely set Steam launch options itself; it can detect a
  missing or stale log and show the steps.
- Disk writes are small.

## Correction: where Dota keeps its settings now
- `userdata/<id>/570/remote/cfg/config.cfg` is **stale**: last written 2015 on this Mac.
- Current Dota keeps client settings in `userdata/<id>/570/local/cfg/machine_convars.vcfg`: a KeyValues file of
  `"name" "value"` pairs with `true`/`false` values. It **does** store default values, and is written at launch and
  shutdown. (An earlier version of this note named `user_convars_0_slot0.vcfg` and said only non-default values are
  stored; both were wrong.)
- The mouse-lock convar is `dota_mouse_window_lock`; `in_lock_mouse_to_window` no longer exists. MacDoats 0.3.0
  reads `machine_convars.vcfg`.
