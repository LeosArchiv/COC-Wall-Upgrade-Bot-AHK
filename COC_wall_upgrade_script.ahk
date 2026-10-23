#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance Force

CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
SetTitleMatchMode, 2

; Pure decision logic (no screen, no window): PointInRect, RectSignature,
; GeometryStale, ToleranceValid, GetTolerance, JoinImages, UpgradeCycleDue,
; LoadImagePaths, EmptyGroups. selfcheck.ahk includes the same file.
#Include %A_ScriptDir%\logic.ahk

; === Log Initialization ===
loggingBroken := false ; set before the first Log call, not after it
logFilePath := InitLogging()

; === Window Identifier -> COC Emulator ===
TargetWin := "ahk_class CROSVM_1 ahk_exe crosvm.exe"

; === Configuration ================================================================
; Every number below was measured on one setup. A wrong one makes the bot click
; somewhere real, so each says what it assumes. Screen coordinates are checked
; against the emulator window before use; the bot stops instead of clicking blind.

; Confirm button of the upgrade dialog, in SCREEN coordinates, measured with F9.
; ASSUMES the emulator window sits where it sat during that measurement. It is the
; only click the bot cannot verify by image, because no PNG for this button exists
; yet. ConfirmUpgrade refuses when the point is not inside the emulator window.
ConfirmClickX := 1300
ConfirmClickY := 925

; Nudge the cursor down off the builder icon before the wall search starts.
; ASSUMES a window tall enough for 200 px below the builder; checked before moving.
BuilderNudgeY := 200

; Click this far into a found image, instead of at its top left corner.
; ASSUMES every PNG is at least 20 x 20 px.
ImageClickOffset := 10

AttacksPerUpgradeCycle := 6   ; attacks before the bot spends the loot
MaxScrollAttempts := 9        ; wall search: scroll bursts before giving up
ScrollBurst := 3              ; wheel notches per burst

; === Timing =======================================================================
; A fixed Sleep is a guess about how long the game needs. Where the bot waits for
; something it can see, it polls for it with a timeout instead. The remaining
; sleeps are settle time after an input, not "wait until the screen changed".
MainTimerMs := 1000           ; how often the main routine looks for the popup
PollIntervalMs := 300         ; between two image searches of the same wait
SettleMs := 500               ; after a found image / before and after a click
DialogSettleMs := 500         ; after the resource button, before the confirm click
BuilderTimeoutMs := 30000     ; wait for a free builder
WallAttemptMs := 400          ; wall search per scroll position
ResourceTimeoutMs := 5000     ; wait for the gold / elixir upgrade button
ScrollSettleMs := 700         ; after a scroll burst, before searching again
VillageLoadWaitMs := 8000     ; village to finish loading before the attack starts
PopupWaitTimeoutMs := 300000  ; Back-to-Home popup after an attack (5 min)
AttackTimeoutMs := 180000     ; Attack.exe to finish by itself (3 min)

; === Image Files (Load dynamically from folders) ===
image_groups := ["builder", "wall", "gold", "elexier", "popup"]
images := LoadImagePaths(image_groups, A_ScriptDir)

; A group without a single PNG can never be found. Without this the bot would wait
; forever for a popup that nothing is searching for. ToggleScript refuses to start
; while this is set; the message box comes last, because it blocks everything after
; it until the user clicks it away.
ImageSetupError := EmptyGroups(images, image_groups)

; === Status Variables ===
MonitoringActive := false
runCounter := 0 ; Counts the runs until the upgrade cycle
lastLogMessage := "" ; Suppresses identical consecutive log lines (polling spam)
WinSig := "" ; Window geometry at the moment F2 started. Any change invalidates every
             ; coordinate taken before it, so the run stops.

if (ImageSetupError != "") {
    Log("IMAGE SETUP ERROR: no PNG found for group(s): " . ImageSetupError)
    setupMsg := "⚠️ No PNG files found for group(s): " . ImageSetupError . "`n`nThe bot cannot search for them and refuses to start."
    MsgBox, 48, COC Wall Upgrade Bot, %setupMsg%
}
loggingBroken := false

; === Hotkeys ===
F2::ToggleScript()
F3::
    MsgBox, 64, COC Popup Monitor - Help, Script Hotkeys:`n`n• F2 - Start/Stop `n• F3 - Show this help`n• F4 - Test wall Images`n• F5 - Test Gold Images`n• F6 - Test Elexier Images`n• F7 - Test Builder Images`n• F8 - Test Popup Images`n• ESC - Exit script (kills COC macro)`n`nNotes:`n- Make sure "popup.png" is in script folder`n- F2 only starts when the COC window is open`n- Searches are limited to the COC window, not the whole desktop`n- Every failed search names the image in logs\`n- The run stops when the COC window moves, is resized, disappears or gets covered`n- Works on all monitors`n- COC macro gets killed when stopping/exiting
return
F4::CheckImageGroupWithPopup("wall")
F5::CheckImageGroupWithPopup("gold")
F6::CheckImageGroupWithPopup("elexier")
F7::CheckImageGroupWithPopup("builder")
F8::CheckImageGroupWithPopup("popup")

F9::
    MouseGetPos, xpos, ypos
    ToolTip, Mouse Position: %xpos%`, %ypos%
    SetTimer, RemoveToolTip, 2000
return

Esc::ExitAppWithKill()

; === Script Start/Stop with F2 ===
ToggleScript() {
    global MonitoringActive, TargetWin, WinSig, ImageSetupError, MainTimerMs

    ; Refuse to start unless the emulator window is really there. Without this the
    ; routine searched the whole desktop and clicked whatever happened to match.
    if (!MonitoringActive && !WinExist(TargetWin)) {
        Log("Start refused: emulator window not found (" . TargetWin . ").")
        ToolTip, ❌ Clash of Clans window not found - script not started
        SetTimer, RemoveToolTip, 3000
        return
    }
    if (!MonitoringActive && ImageSetupError != "") {
        Log("Start refused: no PNG for group(s) " . ImageSetupError . ".")
        msg := "❌ No images for: " . ImageSetupError . " - script not started"
        ToolTip, %msg%
        SetTimer, RemoveToolTip, 3000
        return
    }

    MonitoringActive := !MonitoringActive

    ; taskkill reports through the exit code: 0 = killed, 128 = nothing to kill.
    ; Neither is fatal, but a different code means taskkill itself failed.
    RunWait, taskkill /F /IM "Attack.exe", , Hide UseErrorLevel
    killResult := ErrorLevel
    if (killResult != 0 && killResult != 128)
        Log("taskkill for Attack.exe returned " . killResult . ".")
    Sleep, 300

    if (MonitoringActive) {
        ; Remember where the window is. Everything measured from now on is only
        ; valid while it stays there.
        WinSig := WindowRect(wx, wy, ww, wh)
        if (WinSig = "") {
            MonitoringActive := false
            Log("Start refused: emulator window has no usable position or is minimized.")
            ToolTip, ❌ COC window minimized or unreadable - script not started
            SetTimer, RemoveToolTip, 3000
            return
        }
        Log("Script enabled. Emulator window at " . WinSig . " (x|y|w|h).")
        ToolTip, ✅ Macro activated - waiting for the Back-to-Home button
        SetTimer, StartRoutine, %MainTimerMs%
    } else {
        Log("Script disabled.")
        ReleaseMouseButtons()
        ToolTip, ❌ Macro stopped
        SetTimer, StartRoutine, Off
    }
    SetTimer, RemoveToolTip, 2000
}

; === Main Routine ===
StartRoutine:
    global runCounter

    ; 1. ALWAYS wait for and click the initial popup first.
    ;    ClickImageInGroup only clicks when the image was actually found.
    ;    Nothing is logged before this point, so a long wait leaves one line in the
    ;    log ("Not found: popup\...") instead of two per second.
    if !ClickImageInGroup(images["popup"], 0, ImageClickOffset, ImageClickOffset) {
        return ; Ends the routine if no popup is found - nothing was clicked
    }

    Log("--- Popup found and clicked, starting cycle (run " . runCounter . ") ---")
    if !SleepStoppable(SettleMs)
        return

    runCounter++ ; Increment counter
    Log("Run counter is now: " . runCounter)

    ; When the configured number of runs is complete, execute the upgrade cycle
    if UpgradeCycleDue(runCounter, AttacksPerUpgradeCycle) {
        Log("Run counter reached " . AttacksPerUpgradeCycle . ". Starting upgrade cycle.")
        runCounter := 0 ; Reset counter
        Log("Counter reset to 0.")

        ; 2. Single, continuous loop for the upgrade cycle
        Loop {
            ; Covers F2 as well as a window that moved, was resized, closed or got
            ; covered by another window while this cycle was running.
            if !BotContextOk()
                break

            ; --- Search for builder ---
            Log("Searching for a free builder...")
            if !ClickImageInGroup(images["builder"], BuilderTimeoutMs) {
                Log("No free builder found within " . Round(BuilderTimeoutMs / 1000) . "s. Breaking upgrade loop.")
                break ; No builder found, exit loop
            }
            Log("Builder found and clicked.")
            if !SleepStoppable(SettleMs)
                break

            ; --- Move mouse off the builder icon ---
            MouseGetPos, nudgeFromX, nudgeFromY
            if !MoveWithinWindow(nudgeFromX, nudgeFromY + BuilderNudgeY, "builder nudge")
                break
            if !SleepStoppable(SettleMs)
                break

            ; --- Search for wall (with scrolling) ---
            Log("Searching for a wall...")
            ScrollAttempts := 0
            wallFound := false
            Loop {
                if !BotContextOk()
                    break
                if ClickImageInGroup(images["wall"], WallAttemptMs) {
                    wallFound := true
                    Log("Wall found and clicked.")
                    break
                }
                if (ScrollAttempts >= MaxScrollAttempts) {
                    Log("No wall found after " . MaxScrollAttempts . " scroll attempts.")
                    break
                }
                if !ScrollDownInGame(ScrollBurst)
                    break
                if !SleepStoppable(ScrollSettleMs)
                    break
                ScrollAttempts++
            }

            if (!wallFound) {
                Log("Breaking upgrade loop because no wall was found.")
                break ; No wall found, exit loop
            }

            ; --- Search for Gold or Elixir ---
            Log("Searching for Gold or Elixir to upgrade...")
            goldAndElexier := images["gold"].Clone()
            for _, img in images["elexier"] {
                goldAndElexier.Push(img)
            }

            if !ClickImageInGroup(goldAndElexier, ResourceTimeoutMs) {
                Log("No Gold or Elixir button found. Breaking upgrade loop.")
                break ; No resources found, exit loop
            }
            Log("Resource found and clicked.")

            ; Confirm dialog. ponytail: still a fixed coordinate, no image exists for
            ; this button yet. Add a confirm/*.png group and route it through
            ; ClickImageInGroup when it misfires.
            if !SleepStoppable(DialogSettleMs)
                break
            if !SafeClick(ConfirmClickX, ConfirmClickY, "upgrade confirm button")
                break
            if !SleepStoppable(SettleMs)
                break
            Log("Upgrade initiated. Looping back to find next builder.")

            ; The loop starts over (searches for builder again)
        }
        if !SleepStoppable(MainTimerMs)
            return
        ; After the upgrade attempt (successful or not), proceed to attack
        Log("Upgrade cycle finished. Starting attack.")
        SetTimer, StartRoutine, Off ; Pause the main routine
        RunAngriff()
        WaitForPopupAndRestart() ; Wait for popup and then restart
        return
    }
    ; 3. Start attack if it's not the upgrade cycle's turn yet. The wait is settle
    ;    time for the village to finish loading; there is no image for "loaded".
    if !SleepStoppable(VillageLoadWaitMs)
        return
    Log("Starting attack.")
    SetTimer, StartRoutine, Off ; Pause the main routine
    RunAngriff()
    WaitForPopupAndRestart() ; Wait for popup and then restart

return

WaitForPopupAndRestart() {
    global images, MonitoringActive, PopupWaitTimeoutMs, MainTimerMs
    Log("Now waiting for the popup to restart the main loop...")
    start := A_TickCount
    Loop {
        ; Honour a stop. SetTimer ... Off does not abort a running thread, so without
        ; this check a stopped script re-armed its own timer and carried on clicking.
        ; BotContextOk also ends the run when the window moved or disappeared.
        if (!MonitoringActive) {
            Log("Stop requested. Not restarting the main routine.")
            return
        }
        if !BotContextOk()
            return
        if FindImageInGroup(images["popup"], x, y) {
            Log("Popup found. Restarting main routine.")
            SetTimer, StartRoutine, %MainTimerMs%
            return
        }
        ; Bounded, because waiting forever is how a bot ends up clicking into an ad,
        ; a disconnect dialog or a loading screen it cannot read.
        if (A_TickCount - start >= PopupWaitTimeoutMs) {
            StopBot("no Back-to-Home popup for " . Round(PopupWaitTimeoutMs / 1000) . " s - the game is not where the bot expects it")
            return
        }
        ; Same once-a-second cadence as the main timer: three full-window image
        ; searches per poll are not free.
        if !SleepStoppable(MainTimerMs)
            return
    }
}

RunAngriff() {
    global MonitoringActive, AttackTimeoutMs
    ; Both call sites come from an already running thread that F2 cannot abort, so the
    ; stop has to be honoured here, before the macro sends any input.
    if (!MonitoringActive) {
        Log("Attack skipped: script was stopped.")
        return
    }
    if !BotContextOk()
        return

    attackExe := A_ScriptDir . "\Attack.exe"
    if !FileExist(attackExe) {
        StopBot("Attack.exe is missing in " . A_ScriptDir)
        return
    }

    ; UseErrorLevel: without it a failed Run shows a dialog and silently exits this
    ; thread, leaving the bot started but doing nothing.
    Log("Executing Attack.exe")
    Run, "%attackExe%", %A_ScriptDir%, UseErrorLevel, attackPid
    runResult := ErrorLevel
    if (runResult = "ERROR" || attackPid = "") {
        StopBot("Attack.exe could not be started (A_LastError " . A_LastError . ")")
        return
    }

    ; Wait for the macro to actually finish instead of sleeping a guessed 15 s: a
    ; recording that runs long used to have the bot click into the middle of it.
    waited := 0
    Loop {
        Process, WaitClose, %attackPid%, 0.5
        stillRunning := ErrorLevel
        if (!stillRunning) {
            Log("Attack.exe finished after about " . Round(waited / 1000) . " s.")
            return
        }
        waited += 500
        if (!MonitoringActive) {
            Process, Close, %attackPid%
            StopBot("stop requested during the attack - Attack.exe was killed")
            return
        }
        if (waited >= AttackTimeoutMs) {
            Process, Close, %attackPid%
            StopBot("Attack.exe still running after " . Round(AttackTimeoutMs / 1000) . " s - killed it")
            return
        }
    }
}

; ===================================================================================
; === Run state: stopping, waiting, and "is the game still where it was?" ===========
; ===================================================================================

; One place that ends a run, so a stop always leaves the same state behind: no timer,
; no held mouse button, one line in the log saying why.
StopBot(reason) {
    global MonitoringActive
    MonitoringActive := false
    SetTimer, StartRoutine, Off
    ReleaseMouseButtons()
    Log("STOP: " . reason)
    msg := "⛔ Stopped: " . reason
    ToolTip, %msg%
    SetTimer, RemoveToolTip, 6000
}

; A stop must not leave a button down: the user would take over mid-drag, dragging
; their own village around. Click presses and releases in one go, but a stop can land
; between the two.
ReleaseMouseButtons() {
    if GetKeyState("LButton")
        Click, Up
    if GetKeyState("RButton")
        Click, Up Right
}

; Sleep that a stop can cut short. A hotkey does interrupt a Sleep in v1, but the
; sleeping thread resumes afterwards, so every wait has to look at the flag itself.
SleepStoppable(ms) {
    global MonitoringActive
    slept := 0
    while (slept < ms) {
        if (!MonitoringActive)
            return false
        chunk := (ms - slept > 200) ? 200 : ms - slept
        Sleep, %chunk%
        slept += chunk
    }
    return MonitoringActive
}

; Position and size of the emulator window as "x|y|w|h", or "" when it cannot be
; used. WinGetPos does not report through ErrorLevel in v1, it blanks its output
; variables, so a blank check is the only test there is.
WindowRect(ByRef wx, ByRef wy, ByRef ww, ByRef wh) {
    global TargetWin
    wx := ""
    wy := ""
    ww := ""
    wh := ""
    if !WinExist(TargetWin)
        return ""
    ; A minimized window reports off-screen coordinates and ImageSearch needs the
    ; region to be visible, so there is nothing to search. WinGet blanks its output
    ; if the window vanished between the two calls.
    WinGet, winState, MinMax, %TargetWin%
    if (winState = "" || winState = -1)
        return ""
    WinGetPos, wx, wy, ww, wh, %TargetWin%
    return RectSignature(wx, wy, ww, wh)
}

; Is the game still where the bot last saw it? Called before every click, every
; scroll and in every wait. Ends the run on anything it can detect.
BotContextOk() {
    global MonitoringActive, WinSig
    if (!MonitoringActive)
        return false
    sig := WindowRect(wx, wy, ww, wh)
    if (sig = "") {
        StopBot("emulator window is gone, minimized or has no size")
        return false
    }
    if GeometryStale(WinSig, sig) {
        StopBot("emulator window moved or was resized (" . WinSig . " -> " . sig . ") - every measured coordinate is stale")
        return false
    }
    return true
}

; The only place in the script that presses a mouse button on the game. Refuses when
; the point is outside the emulator window, or when another window covers that point.
; MouseGetPos reports the top-level window under the cursor (verified on 1.1.37.02:
; over a child control it still returns the parent), so moving first and looking
; second is a real test for "is the game actually under the cursor".
SafeClick(x, y, what) {
    global TargetWin
    if !MoveWithinWindow(x, y, what)
        return false
    hTarget := WinExist(TargetWin)
    MouseGetPos, , , hUnder
    if (hUnder != hTarget) {
        StopBot("refused to click " . what . " at " . x . "/" . y . " - another window covers that point")
        return false
    }
    Click
    return true
}

; Move the cursor, but only to a point inside the emulator window. This is what turns
; a stale hardcoded coordinate from a click somewhere real into a clean stop.
MoveWithinWindow(x, y, what) {
    if !BotContextOk()
        return false
    WindowRect(wx, wy, ww, wh)
    if !PointInRect(x, y, wx, wy, ww, wh) {
        StopBot("refused to aim at " . x . "/" . y . " for " . what . " - outside the emulator window " . wx . "|" . wy . "|" . ww . "|" . wh)
        return false
    }
    MouseMove, %x%, %y%, 0
    return true
}

; The wheel goes to the active window, not necessarily to the one under the cursor,
; so scrolling while the emulator sits in the background would scroll whatever the
; user is reading. Both conditions are required because the documentation does not
; say which window receives a synthetic wheel event.
ScrollDownInGame(bursts) {
    global MonitoringActive, TargetWin
    if !BotContextOk()
        return false
    if !WinActive(TargetWin) {
        StopBot("refused to scroll - the emulator window is not the active window")
        return false
    }
    Loop, %bursts% {
        if (!MonitoringActive)
            return false
        Send, {WheelDown}
        Sleep, 30
    }
    return true
}

; ===================================================================================
; === Image search - THE ONLY PLACE THAT CALLS ImageSearch ==========================
; ===================================================================================
; AutoHotkey v1 ImageSearch sets ErrorLevel: 0 = found, 1 = not found,
; 2 = search could not be conducted (file unreadable, or a badly formatted option).
; Only 0 may be treated as a hit. Whether AHK blanks the output variables on 1 and 2
; is not documented (1.1.37.02 does, as section 9 of selfcheck.ahk shows), so
; FindImage blanks them itself. The old code relied on them and clicked the
; coordinates of a previous, unrelated find.

; Search region = the emulator window, never the whole desktop.
; Returns false when the window is gone, so no search can run against the desktop.
SearchRect(ByRef x1, ByRef y1, ByRef x2, ByRef y2) {
    if (WindowRect(wx, wy, ww, wh) = "")
        return false
    x1 := wx
    y1 := wy
    x2 := wx + ww
    y2 := wy + wh
    return true
}

; Single search. Fills foundX/foundY ONLY on a real hit; blanks them otherwise, so a
; caller that ignores the return value cannot reuse a stale coordinate.
FindImage(image, ByRef foundX, ByRef foundY, tolerance := "") {
    foundX := ""
    foundY := ""

    if !SearchRect(x1, y1, x2, y2) {
        Log("Search skipped: emulator window not available.")
        return false
    }
    if (tolerance = "")
        tolerance := GetTolerance(image)
    ; A malformed tolerance fails with the same ErrorLevel 2 as a missing file.
    ; Separating the two here means the log names the real cause.
    if !ToleranceValid(tolerance) {
        Log("IMAGE ERROR: tolerance '" . tolerance . "' for " . image . " is not *0 to *255.")
        return false
    }

    ImageSearch, hitX, hitY, x1, y1, x2, y2, %tolerance% %A_ScriptDir%\%image%
    el := ErrorLevel

    if (el = 0) {
        foundX := hitX
        foundY := hitY
        return true
    }
    if (el != 1) {
        ; ErrorLevel 2: the file could not be opened or the options are malformed.
        ; Loud, because this never fixes itself by waiting.
        Log("IMAGE ERROR: could not search for " . image . " (tolerance " . tolerance . "). File missing or unreadable?")
        msg := "⚠️ Image error: " . image
        ToolTip, %msg%
        SetTimer, RemoveToolTip, 4000
    }
    return false
}

; Search a whole group. Same contract: coordinates only on a hit.
FindImageInGroup(imageList, ByRef foundX, ByRef foundY, tolerance := "") {
    foundX := ""
    foundY := ""
    for _, image in imageList {
        if FindImage(image, foundX, foundY, tolerance)
            return true
    }
    return false
}

; Wait up to `timeout` ms for any image of the group and click it. The click lives in
; here, so no call site ever holds a coordinate it has to validate itself.
; timeout 0 = single attempt. Returns false without clicking anything.
ClickImageInGroup(imageList, timeout := 0, offsetX := 0, offsetY := 0, tolerance := "") {
    global PollIntervalMs, SettleMs
    start := A_TickCount
    Loop {
        if !BotContextOk()
            return false
        if FindImageInGroup(imageList, foundX, foundY, tolerance) {
            if !SleepStoppable(SettleMs)
                return false
            if !SafeClick(foundX + offsetX, foundY + offsetY, JoinImages(imageList))
                return false
            return SleepStoppable(SettleMs)
        }
        if (A_TickCount - start >= timeout) {
            Log("Not found: " . JoinImages(imageList))
            return false
        }
        if !SleepStoppable(PollIntervalMs)
            return false
    }
}

; === Image Search with Window Context (F4-F8) ===
CheckImageGroupWithPopup(groupName) {
    global images, TargetWin

    if !images.HasKey(groupName) {
        MsgBox, ⚠️ Image group '%groupName%' not defined.
        return
    }
    if (images[groupName].MaxIndex() = "") {
        MsgBox, ⚠️ Image group '%groupName%' has no PNG file.
        return
    }

    if !WinExist(TargetWin) {
        MsgBox, ❌ Window not found: Clash of Clans Emulator is not running!
        return
    }

    ; Same helper and the same tolerances the main routine uses, so a green test
    ; actually means the main routine will find it too.
    found := false
    for _, imageFile in images[groupName] {
        if FindImage(imageFile, FoundX, FoundY) {
            ToolTip, ✅ %imageFile% found at %FoundX%`, %FoundY%
            Gui, +AlwaysOnTop -Caption +ToolWindow
            Gui, Color, Red
            Gui, Add, Text, x0 y0 w80 h20 Center BackgroundTrans cWhite, ✔ Found
            Gui, Show, x%FoundX% y%FoundY% w80 h20 NoActivate
            SetTimer, CloseTestGui, 2000
            found := true
            break ; Stop searching after first find in group
        }
    }

    if (!found) {
        tried := JoinImages(images[groupName])
        Log("Test '" . groupName . "': nothing found. Tried: " . tried)
        ToolTip, ❌ No image from group '%groupName%' found: %tried%
    }
    SetTimer, RemoveToolTip, 3000
}

CloseTestGui:
    Gui, Destroy
    SetTimer, CloseTestGui, Off
return

RemoveToolTip:
    ToolTip
    SetTimer, RemoveToolTip, Off
return

ExitAppWithKill() {
    Log("Exit hotkey pressed. Killing Attack.exe and exiting script.")
    ReleaseMouseButtons()
    RunWait, taskkill /F /IM "Attack.exe", , Hide UseErrorLevel
    ExitApp
}

; === Logging Functions ===
InitLogging() {
    global logFilePath, loggingBroken
    logDir := A_ScriptDir . "\logs"
    if !FileExist(logDir) {
        FileCreateDir, %logDir%
        if (ErrorLevel) {
            loggingBroken := true
            logFilePath := ""
            logMsg := "⚠️ Could not create the log folder:`n" . logDir . "`n`nThe bot runs, but nothing is written down."
            MsgBox, 48, COC Wall Upgrade Bot, %logMsg%
            return ""
        }
    }

    FormatTime, time, , yyyy-MM-dd_HH-mm-ss
    ; Set the global BEFORE logging - otherwise the first line goes nowhere.
    logFilePath := logDir . "\log_" . time . ".txt"
    Log("Logging initialized. Log file: " . logFilePath)
    return logFilePath
}

Log(message) {
    global logFilePath, lastLogMessage, loggingBroken
    if (logFilePath = "" || loggingBroken)
        return
    if (message = lastLogMessage)
        return ; Identical consecutive line: a poll that is still waiting, not news
    lastLogMessage := message
    FormatTime, time, , HH:mm:ss
    line := time . " - " . message . "`n"
    FileAppend, %line%, %logFilePath%
    ; A log that silently stops being written is worse than no log, and FileAppend is
    ; the one command here that fails for ordinary reasons (disk full, folder gone).
    if (ErrorLevel) {
        loggingBroken := true
        msg := "⚠️ Log cannot be written any more: " . logFilePath
        ToolTip, %msg%
        SetTimer, RemoveToolTip, 5000
    }
}
