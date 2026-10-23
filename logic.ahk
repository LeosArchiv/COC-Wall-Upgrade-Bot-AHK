; ===================================================================================
; === Pure decision logic ===========================================================
; ===================================================================================
; Nothing in here looks at the screen, at a window or at a global variable. Every
; function takes its inputs and returns a value, which is the only reason selfcheck
; .ahk can call them with made-up inputs and tell pass from fail without the game
; running. Included by COC_wall_upgrade_script.ahk and by selfcheck.ahk.
; AutoHotkey v1 only.

; Tolerance per image group. Looser where the game draws the object over changing
; ground (walls), tighter where the colour carries the meaning (gold or elixir text).
; ImageSearch accepts *0 to *255 only. Anything outside that range is a badly
; formatted option and makes the search fail with ErrorLevel 2.
GetTolerance(imageFile) {
    if InStr(imageFile, "wall") || InStr(imageFile, "mauer") {
        return "*130"
    }
    else if InStr(imageFile, "gold") || InStr(imageFile, "elexier") {
        return "*100"
    }
    else if InStr(imageFile, "builder") {
        return "*60"
    }
    else {
        return "*30"
    }
}

; Joined with " / " on purpose: this string is also passed to ToolTip, whose text
; parameter would treat a comma as the start of the X coordinate.
JoinImages(imageList) {
    out := ""
    for _, image in imageList
        out .= (out = "" ? "" : " / ") . image
    return out
}

; Image file names per group, relative to baseDir. Filesystem only, no screen.
LoadImagePaths(groups, baseDir) {
    loaded_images := {}
    for _, groupName in groups
    {
        loaded_images[groupName] := []
        Loop, Files, %baseDir%\%groupName%\*.png
        {
            loaded_images[groupName].Push(groupName . Chr(92) . A_LoopFileName)
        }
    }
    return loaded_images
}
