#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance Force

CoordMode, Pixel, Screen
CoordMode, Mouse, Screen
SetTitleMatchMode, 2

; Pure decision logic (no screen, no window): GetTolerance, JoinImages,
; LoadImagePaths. Kept separate so selfcheck.ahk can call the same code the bot runs.
#Include %A_ScriptDir%\logic.ahk

; === Log Initialization ===
logFilePath := InitLogging()

; === Window Identifier -> COC Emulator ===
TargetWin := "ahk_class CROSVM_1 ahk_exe crosvm.exe"

; === Image Files (Load dynamically from folders) ===
images := {}
image_groups := ["builder", "wall", "gold", "elexier", "popup"]

images := LoadImagePaths(image_groups, A_ScriptDir)




; === Status Variables ===
MonitoringActive := false
runCounter := 0 ; Counts the runs until the upgrade cycle
lastLogMessage := "" ; Suppresses identical consecutive log lines (polling spam)

; === Hotkeys ===
F2::ToggleScript()
F3::
    MsgBox, 64, COC Popup Monitor - Help, Script Hotkeys:`n`n• F2 - Start/Stop `n• F3 - Show this help`n• F4 - Test wall Images`n• F5 - Test Gold Images`n• F6 - Test Elexier Images`n• F7 - Test Builder Images`n• F8 - Test Popup Images`n• ESC - Exit script (kills COC macro)`n`nNotes:`n- Make sure "popup.png" is in script folder`n- F2 only starts when the COC window is open`n- Searches are limited to the COC window, not the whole desktop`n- Every failed search names the image in logs\`n- Works on all monitors`n- COC macro gets killed when stopping/exiting
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
    global MonitoringActive, TargetWin

    ; Refuse to start unless the emulator window is really there. Without this the
    ; routine searched the whole desktop and clicked whatever happened to match.
    if (!MonitoringActive && !WinExist(TargetWin)) {
        Log("Start refused: emulator window not found (" . TargetWin . ").")
        ToolTip, ❌ Clash of Clans window not found - script not started
        SetTimer, RemoveToolTip, 3000
        return
    }

    MonitoringActive := !MonitoringActive

    RunWait, taskkill /F /IM "Attack.exe", , Hide
    Sleep, 300

    if (MonitoringActive) {
        Log("Script enabled.")
        ToolTip, ✅ Macro activated - waiting for the Back-to-Home button
        SetTimer, StartRoutine, 1000
    } else {
        Log("Script disabled.")
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
    if !ClickImageInGroup(images["popup"], 0, 10, 10) {
        return ; Ends the routine if no popup is found - nothing was clicked
    }

    Log("--- Popup found and clicked, starting cycle (run " . runCounter . ") ---")
    Sleep, 500

    runCounter++ ; Increment counter
    Log("Run counter is now: " . runCounter)

    ; When 10 runs are complete, execute the upgrade cycle //change this to any number you want
    if (runCounter >= 6) {
        Log("Run counter reached 6. Starting upgrade cycle.")
        runCounter := 0 ; Reset counter
        Log("Counter reset to 0.")

        ; 2. Single, continuous loop for the upgrade cycle
        Loop {
            if (!MonitoringActive)
                break ; F2 was pressed while this cycle was running

            ; --- Search for builder ---
            Log("Searching for a free builder...")
            if !ClickImageInGroup(images["builder"], 30000) {
                Log("No free builder found within 30s. Breaking upgrade loop.")
                break ; No builder found, exit loop
            }
            Log("Builder found and clicked.")
            Sleep, 300

            ; --- Move mouse down ---
            MouseMove, 0, 200, 0, R
            Sleep, 300

            ; --- Search for wall (with scrolling) ---
            Log("Searching for a wall...")
            ScrollAttempts := 0
            wallFound := false
            Loop {
                if ClickImageInGroup(images["wall"], 400) {
                    wallFound := true
                    Log("Wall found and clicked.")
                    break
                }
                if (ScrollAttempts >= 9) {
                    Log("No wall found after 9 scroll attempts.")
                    break
                }
                Loop, 3 {
                    Send, {WheelDown}
                    Sleep, 30
                }
                Sleep, 700 ; Adjusted wait time
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

            if !ClickImageInGroup(goldAndElexier, 5000) {
                Log("No Gold or Elixir button found. Breaking upgrade loop.")
                break ; No resources found, exit loop
            }
            Log("Resource found and clicked.")

            ; Confirm dialog. ponytail: still a fixed coordinate, no image exists for
            ; this button yet. Add a confirm/*.png group and route it through
            ; ClickImageInGroup when it misfires.
            Sleep, 500
            Click, 1300, 925
            Sleep, 400
            Log("Upgrade initiated. Looping back to find next builder.")
            
            ; The loop starts over (searches for builder again)
        }
         Sleep, 1000
        ; After the upgrade attempt (successful or not), proceed to attack
        Log("Upgrade cycle finished. Starting attack.")
        SetTimer, StartRoutine, Off ; Pause the main routine
        RunAngriff()
        WaitForPopupAndRestart() ; Wait for popup and then restart
        return
    }
    Sleep, 8000
    ; 3. Start attack if it's not the upgrade cycle's turn yet
    Log("Starting attack.")
    SetTimer, StartRoutine, Off ; Pause the main routine
    RunAngriff()
    WaitForPopupAndRestart() ; Wait for popup and then restart
    
return

WaitForPopupAndRestart() {
    global images, MonitoringActive
    Log("Now waiting for the popup to restart the main loop...")
    Loop {
        ; Honour a stop. SetTimer ... Off does not abort a running thread, so without
        ; this check a stopped script re-armed its own timer and carried on clicking.
        if (!MonitoringActive) {
            Log("Stop requested. Not restarting the main routine.")
            return
        }
        if FindImageInGroup(images["popup"], x, y) {
            Log("Popup found. Restarting main routine.")
            SetTimer, StartRoutine, 1000 ; Reactivate timer
            return
        }
        Sleep, 1000 ; Wait 1 second between search attempts
    }
}

RunAngriff() {
    global MonitoringActive, TargetWin
    ; Both call sites come from an already running thread that F2 cannot abort, so the
    ; stop has to be honoured here, before the macro sends any input.
    if (!MonitoringActive) {
        Log("Attack skipped: script was stopped.")
        return
    }
    if !WinExist(TargetWin) {
        Log("Attack skipped: emulator window is gone.")
        return
    }
    Log("Executing Attack.exe")
    Run, Attack.exe
    Sleep, 15000
    Log("Attack.exe should be finished.")
}

; ===================================================================================
; === Image search - THE ONLY PLACE THAT CALLS ImageSearch OR CLICKS A RESULT ========
; ===================================================================================
; AutoHotkey v1 ImageSearch sets ErrorLevel: 0 = found, 1 = not found,
; 2 = search could not be conducted (file unreadable, or a badly formatted option).
; Only 0 may be treated as a hit. On 1 the output variables are blanked by AHK, on 2
; they are not touched at all - which is how a click used to land on the coordinates
; of a previous, unrelated find.

; Search region = the emulator window, never the whole desktop.
; Returns false when the window is gone, so no search can run against the desktop.
SearchRect(ByRef x1, ByRef y1, ByRef x2, ByRef y2) {
    global TargetWin
    if !WinExist(TargetWin)
        return false
    ; A minimized window reports off-screen coordinates and ImageSearch needs the
    ; region to be visible, so there is nothing to search.
    WinGet, winState, MinMax, %TargetWin%
    if (winState = -1)
        return false
    WinGetPos, wx, wy, ww, wh, %TargetWin%
    if (ww = "" || wh = "" || ww < 1 || wh < 1)
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
        ToolTip, ⚠️ Image error: %image%
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
    global MonitoringActive
    start := A_TickCount
    Loop {
        if FindImageInGroup(imageList, foundX, foundY, tolerance) {
            Sleep, 500
            clickX := foundX + offsetX
            clickY := foundY + offsetY
            Click, %clickX%, %clickY%
            Sleep, 500
            return true
        }
        if (!MonitoringActive || A_TickCount - start >= timeout) {
            Log("Not found: " . JoinImages(imageList))
            return false
        }
        Sleep, 300
    }
}

; === Image Search with Window Context (F3-F6) ===
CheckImageGroupWithPopup(groupName) {
    global images, TargetWin

    if !images.HasKey(groupName) {
        MsgBox, ⚠️ Image group '%groupName%' not defined.
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
    RunWait, taskkill /F /IM "Attack.exe", , Hide
    ExitApp
}

; === Logging Functions ===
InitLogging() {
    global logFilePath
    logDir := A_ScriptDir . "\logs"
    if !FileExist(logDir)
        FileCreateDir, %logDir%

    FormatTime, time, , yyyy-MM-dd_HH-mm-ss
    ; Set the global BEFORE logging - otherwise the first line goes nowhere.
    logFilePath := logDir . "\log_" . time . ".txt"
    Log("Logging initialized. Log file: " . logFilePath)
    return logFilePath
}

Log(message) {
    global logFilePath, lastLogMessage
    if (logFilePath = "")
        return
    if (message = lastLogMessage)
        return ; Identical consecutive line: a poll that is still waiting, not news
    lastLogMessage := message
    FormatTime, time, , HH:mm:ss
    FileAppend, %time% - %message%`n, %logFilePath%
}
