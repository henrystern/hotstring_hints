#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; todos
; don't hide if completion menu is active window
; optimize -- store last Trie root and go from there if just a char addition
; context hotstrings

^r::Reload ; for development

If (A_ScriptFullPath = A_LineFile) {
    ; Settings
    Global hotstring_file := "expansions.ahk"
    Global max_rows := 10
    Global min_show_length := 2
    Global min_suggestion_length := 4

    ; Script
    Global gathered_input := InputHook("C V", "{Esc}{Space}{Home}{End}{PgUp}{PgDn}{Left}{Right}{Up}{Down}{Enter},.")
    gathered_input.OnChar := UpdateSuggestions
    gathered_input.NotifyNonText := True
    gathered_input.OnKeyUp := UpdateSuggestions
    gathered_input.OnEnd := ResetWord
    gathered_input.Start()

    make_gui()

    HotIf
    ; extend layer
    Hotkey "~SC03A & ~SC027", ResetWord

    ; normal
    Hotkey "~LButton", ResetWord
    Hotkey "~MButton", ResetWord
    Hotkey "~RButton", ResetWord
    Hotkey "~!Tab", ResetWord

    HotIfWinExist "Completion Menu"
    Hotkey "^Space", KeyboardInsertMatch
    Hotkey "Tab", ChangeFocus.Bind("Down")
    Hotkey "+Tab", ChangeFocus.Bind("Up")
    HotIf

    global word_list := TrieNode()
    num_words := 0
    Loop read, hotstring_file {
        tooltip num_words ", " A_LoopReadLine
        ; if num_words > 1000 {
            ; break
        ; }
        first_two := SubStr(A_LoopReadLine, 1, 2)
        if first_two = "::" {
            AddHotstring(A_LoopReadLine)
        }
        else if first_two = "; " { ; ignore comments
            continue
        }
        else {
            AddWord(A_LoopReadLine)
        }
        num_words += 1
    }

    tooltip
}

make_gui() {
    Global suggestions := Gui("+AlwaysOnTop -Caption", "Completion Menu")
    suggestions.MarginX := 0
    suggestions.MarginY := 0
    suggestions.SetFont("S10", "Verdana")

    global matches := suggestions.Add("ListView", "r" max_rows " w200 +Grid -Multi -ReadOnly -Hdr +Background30363D +CD2A8FF -E0x200 LV0x8000", ["Abbr.", "Word"]) ; E0x200 hides border
    matches.OnEvent("DoubleClick", InsertMatch)
    matches.OnEvent("ItemEdit", ModifyHotstring)

    suggestions.Show("Hide") ; makes gui resizable to correct number of rows on first suggestion
}

AddWord(word) {
    if StrLen(word) >= min_suggestion_length {
        word_list.insert(A_LoopReadLine)
    }
}

AddHotstring(hstring) {
    split := StrSplit(hstring, "::")
    trigger := split[2]
    word := split[3]
    if StrLen(word) >= min_suggestion_length {
        word_list.insert(word, trigger)
    }
}

InsertMatch(matches, row) {
    prefix := gathered_input.Input
    word := matches.GetText(row, 2)
    ResetWord("Click")
    Send SubStr(word, StrLen(prefix) + 1)
    Send "{Space}"
    return
}

KeyboardInsertMatch(*) {
    focused := ListViewGetContent("Count Focused", matches)
    InsertMatch(matches, focused)
    return
}

ChangeFocus(direction, *) {
    focused := ListViewGetContent("Count Focused", matches)
    if direction = "Up" {
        matches.Modify(Max(focused - 1, 1), "+Select +Focus")
    }
    else if direction = "Down" {
        matches.Modify(Mod(focused + 1, rows), "+Select +Focus")
    }
    return
}

ModifyHotstring(matches, row) {
    trigger := matches.GetText(row, 1)
    word := matches.GetText(row, 2)
    FileAppend "`r`n::" trigger "::" word, hotstring_file
    word_list.insert(word, trigger)
    Run hotstring_file
}

ResetWord(called_by) {
    if called_by is String { ; if not inputhook calling itself
        gathered_input.Stop()
    }
    tooltip "Reset due to " gathered_input.EndReason
    suggestions.hide()
    matches.Delete()
    gathered_input.Start()
    return
}

UpdateSuggestions(*) {
    current_word := StrLower(gathered_input.Input)
    tooltip current_word
    if WinActive("Completion Menu") {
        return
    } 
    if StrLen(current_word) < min_show_length {
        suggestions.hide()
        return
    }

    matches.Delete()
    match_list := word_list.match(current_word)
    if not match_list {
        suggestions.hide()
        return
    }

    Global rows := 0
    for match in match_list {
        matches.Add(, match[1], match[2])
        rows += 1
    }

    matches.Modify(1, "+Select +Focus")
    matches.ModifyCol()
    matches.ModifyCol(2, "AutoHdr")

    rows := min(max_rows, rows)
    suggestions.Move(,,,rows * 20) ; will have to change if font size changes

    if CaretGetPos(&x, &y) {
        suggestions.Show("x" x " y" y + 20 " NoActivate")
    }
    else {
        pos := FindActivePos()
        suggestions.Show("x" pos[1] - 200 " y" pos[2] - 10 - rows * 20 " NoActivate")
    }
}

FindActivePos() {
    ; return bounding coordinates of the monitor containing the active window
    num_monitors := MonitorGetCount()
    if WinGetID("A") {
        WinGetPos(&X, &Y, &W, &H, "A")
        R := X + W
        B := Y + H
        return Array(R, B)
    }
    else {
        MonitorGet(, &L, &T, &R, &B)
        return Array(R, B)
    }
}


Class TrieNode
{
    __New() {
        this.root := Map()
    }

    insert(word, abbr:="") {
        current := this.root

        prefix := ""
        Loop Parse, word {
            char := A_LoopField
            prefix := prefix . char
            if not current.Has(char) {
                current[char] := Map()
            }
            current := current[char]
        }

        current["is_word"] := abbr
    }

    match(prefix) {
        current := this.root
        Loop Parse, prefix {
            char := A_LoopField
            if not current.Has(char) {
                return ""
            }
            current := current[char]
        }
        return this.TraverseFromNode(prefix, current)
    }

    TraverseFromNode(prefix, root) {
        stack := Array(Array(prefix, root))
        match_list := Array()
        while stack.Length {
            next := stack.Pop()
            string := next[1]
            node := next[2]
            if node.Has("is_word") {
                match_list.Push(Array(node["is_word"], string)) ; is_word stores hotstring abbreviation
            }
            for char, child in node {
                if char = "is_word" {
                    continue
                }
                stack.Push(Array(string . char, child))
            }
        }
        return match_list
    }
}