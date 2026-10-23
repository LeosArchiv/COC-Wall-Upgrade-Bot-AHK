; ===================================================================================
; === Pure decision logic ===========================================================
; ===================================================================================
; Nothing in here looks at the screen, at a window or at a global variable. Every
; function takes its inputs and returns a value, which is the only reason selfcheck
; .ahk can call them with made-up numbers and tell pass from fail without the game
; running. Included by COC_wall_upgrade_script.ahk and by selfcheck.ahk.
; AutoHotkey v1 only.

; Is the point inside the rectangle? A blank input means "a window that could not be
; read", and nothing is ever inside an unknown rectangle.
PointInRect(x, y, rx, ry, rw, rh) {
    if (x = "" || y = "" || rx = "" || ry = "" || rw = "" || rh = "")
        return false
    return (x >= rx) && (y >= ry) && (x < rx + rw) && (y < ry + rh)
}

; Window geometry as one comparable string. Blank when any part is missing or the
; window has no area, so an unreadable window never compares equal to a readable one.
RectSignature(x, y, w, h) {
    if (x = "" || y = "" || w = "" || h = "")
        return ""
    if (w < 1 || h < 1)
        return ""
    return x . "|" . y . "|" . w . "|" . h
}

; True when the window moved or was resized since the signature was taken: every
; coordinate measured before is then stale. A blank signature on either side is not
; a change, because "no window at all" is a different failure the caller reports
; separately.
GeometryStale(oldSig, newSig) {
    if (oldSig = "" || newSig = "")
        return false
    return (oldSig != newSig)
}

; ImageSearch accepts *0 to *255 only. Anything else is a badly formatted option, and
; a badly formatted option fails with ErrorLevel 2, which looks exactly like a missing
; file. Checked before the search so the log can say which of the two it was.
ToleranceValid(tolerance) {
    if (SubStr(tolerance, 1, 1) != "*")
        return false
    n := SubStr(tolerance, 2)
    if !RegExMatch(n, "^\d+$")
        return false
    return (n >= 0 && n <= 255)
}

; Tolerance per image group. Looser where the game draws the object over changing
; ground (walls), tighter where the colour carries the meaning (gold or elixir text).
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

; After `limit` attacks the bot spends the loot. A limit below 1 would fire the
; upgrade cycle on every single run, so it is treated as 1.
UpgradeCycleDue(counter, limit) {
    if (limit < 1)
        limit := 1
    return (counter >= limit)
}

; Image file names per group, relative to baseDir. Filesystem only, no screen. An
; empty list means the folder is missing or holds no PNG, which is a hard error:
; searching for nothing always "finds nothing" and would look like a game that is
; simply not ready yet.
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

; Names of the groups that have no image at all, joined for a message. Empty string
; means the image setup is complete.
EmptyGroups(images, groups) {
    out := ""
    for _, groupName in groups {
        if (!images.HasKey(groupName) || images[groupName].MaxIndex() = "")
            out .= (out = "" ? "" : " / ") . groupName
    }
    return out
}
