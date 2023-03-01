#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; todos
; read multi line hotstrings maybe a hover tooltip to see entire output
; optimize -- store last Trie root and go from there if just a char addition

^r::Reload ; for development

If (A_ScriptFullPath = A_LineFile) {
    ; Settings
    Global hotstring_file := A_ScriptDir "/expansions.ahk"
    Global max_rows := 10
    Global min_show_length := 2
    Global min_suggestion_length := 4
    Global bg_colour := "2B2A33"
    Global text_colour := "C9C5A2"
    Global try_caret := True ; try to show gui under caret - will only work in some apps

    ; Script
    Run hotstring_file
    Global gathered_input := InputHook("C V", "")
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

    HotIfWinExist "Completion Menu"
    Hotkey "~LButton", CheckClickLocation
    Hotkey "^Space", KeyboardInsertMatch
    Hotkey "Tab", ChangeFocus.Bind("Down")
    Hotkey "+Tab", ChangeFocus.Bind("Up")
    Hotkey "^k", ResetWord   
    HotIf

    global word_list := TrieNode()
    num_words := 0
    Loop read, hotstring_file {
        first_two := SubStr(A_LoopReadLine, 1, 2)
        if first_two = "::" {
            AddHotstring(A_LoopReadLine)
        }
        else {
            continue
        }
        num_words += 1
    }
}

make_gui() {
    Global suggestions := Gui("+AlwaysOnTop +ToolWindow -Caption", "Completion Menu")
    suggestions.MarginX := 0
    suggestions.MarginY := 0
    suggestions.SetFont("S10", "Verdana")

    global matches := suggestions.Add("ListView", "r" max_rows " w200 +Grid -Multi -ReadOnly -Hdr +Background" bg_colour " +C" text_colour " -E0x200", ["Abbr.", "Word"]) ; E0x200 hides border
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
        word_list.insert(trigger, word, True)
    }
}

InsertMatch(matches, row) {
    prefix := gathered_input.Input
    prefix_length := StrLen(prefix)
    word := matches.GetText(row, 2)
    ResetWord("Insert")
    if SubStr(word, 1, prefix_length) = prefix { ; to match case if trigger is a prefix
        Send SubStr(word, prefix_length + 1)
    }
    else {
        Send "{Backspace " prefix_length "}" ; delete the prefix
        Send word
    }
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
        matches.Modify(Mod(focused - 1, rows), "+Select +Focus")
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
    word_list.insert(trigger, word, True)
    Run hotstring_file
}

ResetWord(called_by) {
    if called_by is String { ; if not inputhook calling itself
        gathered_input.Stop()
    }

    suggestions.hide()
    matches.Delete()
    gathered_input.Start()
    return
}

UpdateSuggestions(hook, params*) {
    current_word := StrLower(gathered_input.Input)

    if WinActive("Completion Menu") {
        return
    } 

    if params[1] is Integer { ; if keycode rather than char
        key := GetKeyName(Format("vk{:x}sc{:x}", params[1], params[2]))
        if (key = "Backspace" or key = "LShift" or key = "RShift" or key = "Capslock") {
            return
        }
        else {
            ResetWord("End_Key")
            return
        }
    }
    else if params[1] = " " or params[1] = "`n" or params[1] = Chr(0x1B) { ; Chr(0x1B) = "Esc"
        tooltip "Reset, " params[1]
        ResetWord("End_Key")
        return
    }

    if StrLen(current_word) < min_show_length {
        suggestions.hide()
        return
    }

    match_list := word_list.match(current_word)
    if not match_list {
        suggestions.hide()
        return
    }

    matches.Delete()
    Global rows := 0
    for match in match_list {
        matches.Add(, match[1], match[2])
        rows += 1
    }

    matches.Modify(1, "+Select +Focus")
    matches.ModifyCol()
    matches.ModifyCol(2, "AutoHdr")

    shown_rows := min(max_rows, rows)
    suggestions.Move(,,,shown_rows * 20) ; will have to change if font size changes
    if try_caret and CaretGetPos(&x, &y) {
        suggestions.Show("x" x " y" y + 20 " NoActivate")
    }
    else {
        pos := FindActivePos()
        suggestions.Show("x" pos[1] - 200 " y" pos[2] - 10 - shown_rows * 20 " NoActivate")
    }
}

FindActivePos() {
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

CheckClickLocation(*) {
    MouseGetPos ,, &clicked_window
    if not WinGetTitle(clicked_window) = "Completion Menu" {
        ResetWord("Click")
    }
}

Class TrieNode
{
    __New() {
        this.root := Map()
    }

    insert(word, pair:="", is_abbr:=False) {
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

        if is_abbr {
            current["is_abbr"] := pair
        }
        else {
            current["is_word"] := pair
        }
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
        if root.Has("is_abbr") {
            match_list.Push(Array(prefix, root["is_abbr"])) ; show exact match abbreviations first
        }
        while stack.Length {
            next := stack.Pop()
            string := next[1]
            node := next[2]
            if node.Has("is_word") {
                match_list.Push(Array(node["is_word"], string)) ; is_word stores hotstring abbreviation
            }
            for char, child in node {
                if char = "is_word" or char = "is_abbr" {
                    continue
                }
                stack.Push(Array(string . char, child))
            }
        }
        return match_list
    }
}