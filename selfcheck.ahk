; ===================================================================================
; === Self check ====================================================================
; ===================================================================================
; One file, no test framework. It calls the real functions out of logic.ahk - the same
; file the bot includes - with made-up inputs, and prints one line per case.
;
; Run it from a console and pipe the output, because an uncompiled AutoHotkey script
; only reaches the terminal through a pipe:
;
;   & "C:\Program Files\AutoHotkey\AutoHotkey.exe" .\selfcheck.ahk | Out-Host
;
; Exit code 0 = everything passed, 1 = at least one case failed.
;
; Section 3 touches the screen (it really runs ImageSearch) but clicks nothing and
; needs no emulator. Everything that does need the game - finding a wall, clicking a
; builder, the stop on a covered window - cannot be checked here at all.

#NoEnv
#SingleInstance Off
SetWorkingDir %A_ScriptDir%
CoordMode, Pixel, Screen
#Include %A_ScriptDir%\logic.ahk

checks := 0
failures := 0

Out("COC Wall Upgrade Bot - self check")
Out("AutoHotkey " . A_AhkVersion . ", script folder " . A_ScriptDir)

Out("")
Out("[1] PointInRect - the guard that stops a stale coordinate from being clicked")
Eq("point in the middle is inside", PointInRect(100, 100, 50, 50, 200, 200), true)
Eq("top left corner is inside", PointInRect(50, 50, 50, 50, 200, 200), true)
Eq("bottom right corner is outside", PointInRect(250, 250, 50, 50, 200, 200), false)
Eq("one pixel inside the far edge", PointInRect(249, 249, 50, 50, 200, 200), true)
Eq("left of the window", PointInRect(49, 100, 50, 50, 200, 200), false)
Eq("above the window", PointInRect(100, 49, 50, 50, 200, 200), false)
Eq("nothing is inside an unreadable window", PointInRect(100, 100, "", "", "", ""), false)
Eq("confirm click 1300/925 fits a 1920x1080 window at 0/0", PointInRect(1300, 925, 0, 0, 1920, 1080), true)
Eq("confirm click 1300/925 refused on a 800x600 window", PointInRect(1300, 925, 0, 0, 800, 600), false)
Eq("confirm click 1300/925 refused when the window moved to 1400/100", PointInRect(1300, 925, 1400, 100, 800, 600), false)
Eq("confirm click 1300/925 still fits a window moved to 1000/600", PointInRect(1300, 925, 1000, 600, 800, 600), true)

Out("")
Out("[2] RectSignature / GeometryStale - noticing a window that moved or resized")
Eq("signature of a normal window", RectSignature(10, 20, 1920, 1080), "10|20|1920|1080")
Eq("zero width has no signature", RectSignature(10, 20, 0, 1080), "")
Eq("negative height has no signature", RectSignature(10, 20, 1920, -1), "")
Eq("unreadable window has no signature", RectSignature("", "", "", ""), "")
Eq("same place is not stale", GeometryStale("10|20|1920|1080", "10|20|1920|1080"), false)
Eq("moved window is stale", GeometryStale("10|20|1920|1080", "11|20|1920|1080"), true)
Eq("resized window is stale", GeometryStale("10|20|1920|1080", "10|20|1600|900"), true)
Eq("missing old signature is not reported as stale", GeometryStale("", "10|20|1920|1080"), false)
Eq("missing new signature is not reported as stale", GeometryStale("10|20|1920|1080", ""), false)

Out("")
Out("[3] ToleranceValid - a bad option fails exactly like a missing file")
Eq("*0 is valid", ToleranceValid("*0"), true)
Eq("*255 is valid", ToleranceValid("*255"), true)
Eq("*130 is valid", ToleranceValid("*130"), true)
Eq("*256 is out of range", ToleranceValid("*256"), false)
Eq("*600 is out of range (the old fallback)", ToleranceValid("*600"), false)
Eq("130 without a star is invalid", ToleranceValid("130"), false)
Eq("empty is invalid", ToleranceValid(""), false)
Eq("*-1 is invalid", ToleranceValid("*-1"), false)
Eq("*abc is invalid", ToleranceValid("*abc"), false)

Out("")
Out("[4] GetTolerance - every group gets an option ImageSearch accepts")
Eq("wall", GetTolerance("wall\mauer1.png"), "*130")
Eq("gold", GetTolerance("gold\gold.png"), "*100")
Eq("elexier", GetTolerance("elexier\elexier3.png"), "*100")
Eq("builder", GetTolerance("builder\builder.png"), "*60")
Eq("popup falls back", GetTolerance("popup\popup.png"), "*30")
Eq("an unknown name still gets a valid option", ToleranceValid(GetTolerance("whatever\x.png")), true)

Out("")
Out("[5] JoinImages - the string also goes to ToolTip, which splits on a comma")
list := ["wall\mauer.png", "wall\mauer1.png"]
Eq("joined with slashes", JoinImages(list), "wall\mauer.png / wall\mauer1.png")
Eq("no comma in the joined string", InStr(JoinImages(list), ",") = 0, true)
Eq("empty list joins to nothing", JoinImages([]), "")

Out("")
Out("[6] UpgradeCycleDue - when the bot spends the loot")
Eq("5 of 6 attacks: not yet", UpgradeCycleDue(5, 6), false)
Eq("6 of 6 attacks: now", UpgradeCycleDue(6, 6), true)
Eq("7 of 6 attacks: still now", UpgradeCycleDue(7, 6), true)
Eq("0 attacks: no", UpgradeCycleDue(0, 6), false)
Eq("a limit of 0 is treated as 1", UpgradeCycleDue(1, 0), true)

Out("")
Out("[7] EmptyGroups - a group without a PNG can never be found")
fake := {}
fake["a"] := ["a\one.png"]
fake["b"] := []
Eq("names the empty group", EmptyGroups(fake, ["a", "b"]), "b")
Eq("names a missing group", EmptyGroups(fake, ["a", "c"]), "c")
Eq("complete setup reports nothing", EmptyGroups(fake, ["a"]), "")

Out("")
Out("[8] LoadImagePaths against the real folders")
groups := ["builder", "wall", "gold", "elexier", "popup"]
images := LoadImagePaths(groups, A_ScriptDir)
Eq("no group is empty", EmptyGroups(images, groups), "")
allExist := true
for _, groupName in groups {
    for _, rel in images[groupName] {
        if !FileExist(A_ScriptDir . "\" . rel)
            allExist := false
    }
}
Eq("every listed file exists on disk", allExist, true)
total := 0
for _, groupName in groups
    total += images[groupName].MaxIndex()
Out("    (" . total . " PNG files in " . groups.MaxIndex() . " groups)")

Out("")
Out("[9] ImageSearch premise - this part really searches the screen, it clicks nothing")
searchX2 := A_ScreenWidth - 1
searchY2 := A_ScreenHeight - 1
missing := A_ScriptDir . "\does_not_exist_" . A_TickCount . ".png"
hitX := "untouched"
hitY := "untouched"
ImageSearch, hitX, hitY, 0, 0, %searchX2%, %searchY2%, *30 %missing%
el := ErrorLevel
Eq("a missing file gives ErrorLevel 2, not 'not found'", el, 2)
Out("    (ErrorLevel " . el . ", output variables came back as '" . hitX . "'/'" . hitY . "' after being set to 'untouched' first;")
Out("     1.1.37.02 blanks them even on ErrorLevel 2, but FindImage blanks them itself instead of relying on that)")

badOption := true
for _, groupName in groups {
    for _, rel in images[groupName] {
        tol := GetTolerance(rel)
        ImageSearch, px, py, 0, 0, %searchX2%, %searchY2%, %tol% %A_ScriptDir%\%rel%
        if (ErrorLevel = 2) {
            Out("    ErrorLevel 2 for " . rel . " with tolerance " . tol)
            badOption := false
        }
    }
}
Eq("every repo PNG can be searched for (ErrorLevel 0 or 1, never 2)", badOption, true)

Out("")
Out(failures = 0 ? "ALL " . checks . " CHECKS PASSED" : failures . " of " . checks . " CHECKS FAILED")
rc := failures = 0 ? 0 : 1
ExitApp, %rc%

; --- tiny helpers ------------------------------------------------------------------

Eq(what, got, want) {
    global checks, failures
    checks++
    gotText := got . ""
    wantText := want . ""
    if (gotText == wantText) {
        Out("  PASS  " . what)
        return true
    }
    failures++
    Out("  FAIL  " . what . "  (got '" . gotText . "', expected '" . wantText . "')")
    return false
}

Out(text) {
    line := text . "`n"
    FileAppend, %line%, *
}
