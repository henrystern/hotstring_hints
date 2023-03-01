#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; todos
; read multi line hotstrings maybe a hover tooltip to see entire output
; better hotstring modification and implement adding hotstrings
; add stack for multi word hotstrings
; allow loading multiple hotkey files - with individual options
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
    Global exact_match_word := False
    Global exact_match_hotstring := True
    Global max_prefix_length := 5 ; max number of space separated words to retain and search for matches. Allows matching sentence style hotstrings.

    ; Hotkeys
    HotIf
    Hotkey "~SC03A & ~SC027", ResetWord
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

    ; Objects
    Run hotstring_file
    Global gathered_input := InputHook("C V", "")
    gathered_input.OnChar := UpdateSuggestions
    gathered_input.NotifyNonText := True
    gathered_input.OnKeyUp := UpdateSuggestions
    gathered_input.OnEnd := ResetWord
    gathered_input.Start()

    MakeGui()

    ; Load wordlist
    global word_list := TrieNode()
    num_words := 0
    Loop read, hotstring_file {
        first_two := SubStr(A_LoopReadLine, 1, 2)
        if first_two = "::" {
            LoadHotstring(A_LoopReadLine)
        }
        else {
            continue
        }
        num_words += 1
    }
}

MakeGui() {
    Global suggestions := Gui("+AlwaysOnTop +ToolWindow -Caption", "Completion Menu")
    suggestions.MarginX := 0
    suggestions.MarginY := 0
    suggestions.SetFont("S10", "Verdana")

    global matches := suggestions.Add("ListView", "r" max_rows " w200 +Grid -Multi -ReadOnly -Hdr +Background" bg_colour " +C" text_colour " -E0x200", ["Abbr.", "Word"]) ; E0x200 hides border
    matches.OnEvent("DoubleClick", InsertMatch)
    matches.OnEvent("ItemEdit", ModifyHotstring)

    suggestions.Show("Hide") ; makes gui resizable to correct number of rows on first suggestion
}

LoadWord(word) {
    if StrLen(word) >= min_suggestion_length {
        word_list.Insert(A_LoopReadLine)
    }
}

LoadHotstring(hstring) {
    split := StrSplit(hstring, "::")
    trigger := split[2]
    word := split[3]
    if StrLen(word) >= min_suggestion_length {
        word_list.Insert(word, trigger, "is_word")
        word_list.Insert(trigger, word, "is_hotstring")
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
    word_list.Insert(word, trigger, "is_word")
    word_list.Insert(trigger, word, "is_hotstring")
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

IsEndKey(params) {
    if params[1] is Integer { ; if keycode rather than char
        key := GetKeyName(Format("vk{:x}sc{:x}", params[1], params[2]))
        if (key = "Backspace" or key = "LShift" or key = "RShift" or key = "LControl" or key = "RControl" or key = "Capslock") {
            tooltip "ignored " key
            return True
        }
        else {
            tooltip "reset by " key
            ResetWord("End_Key")
            return True
        }
    }
    else if params[1] = "`n" or params[1] = Chr(0x1B) { ; Chr(0x1B) = "Esc"
        tooltip "reset by " params[1]
        ResetWord("End_Key")
        return True
    }
    else if params[1] = " " {

    }
    else {
        tooltip "added " params[1]
        return False
    }
}

UpdateSuggestions(hook, params*) {
    current_word := StrLower(gathered_input.Input)

    if WinActive("Completion Menu") {
        return
    } 
    else if IsEndKey(params) {
        return
    }
    else if StrLen(current_word) < min_show_length {
        suggestions.hide()
        return
    }

    current_node := word_list.FindNode(current_word)

    if not current_node {
        return
    }

    hotstring_matches := FindMatches(current_word, current_node, "is_hotstring", exact_match_hotstring)
    word_matches := FindMatches(current_word, current_node, "is_word", exact_match_word)

    if not (hotstring_matches or word_matches) {
        suggestions.hide()
        return
    }
    else {
        AddMatchControls(hotstring_matches, word_matches)
        ResizeGui()
        ShowGui()
    }
}

AddMatchControls(hotstring_matches, word_matches) {
    matches.Delete()
    Global rows := 0
    for match in hotstring_matches {
        matches.Add(, match[1], match[2])
        rows += 1
    }
    for match in word_matches {
        matches.Add(, match[1], match[2])
        rows += 1
    }

    matches.Modify(1, "+Select +Focus")
    matches.ModifyCol()
    matches.ModifyCol(2, "AutoHdr")
}

ResizeGui(){
    Global shown_rows := min(max_rows, rows)
    suggestions.Move(,,,shown_rows * 20) ; will have to change if font size changes
}

ShowGui(){
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

FindMatches(current_word, current_node, match_key, exact_match) {
    if exact_match {
        return word_list.MatchWord(current_word, current_node, match_key)
    }
    else {
        return word_list.MatchPrefix(current_word, current_node, match_key)
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

    Insert(word, pair:="", id_key:="is_word") {
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

        current[id_key] := pair
    }

    FindNode(prefix) {
        current := this.root
        Loop Parse, prefix {
            char := A_LoopField
            if not current.Has(char) {
                return ""
            }
            current := current[char]
        }
        return current
    }

    MatchWord(word, root, match_key) {
        match_list := Array()
        if root.Has(match_key) {
            match_list.Push(Array(word, root[match_key]))
        }
        return match_list
    }

    MatchPrefix(prefix, root, match_key) {
        stack := Array(Array(prefix, root))
        match_list := Array()
        while stack.Length {
            next := stack.Pop()
            string := next[1]
            node := next[2]
            for char, child in node {
                if char = match_key {
                    match_list.Push(Array(node["is_word"], string)) ; is_word stores hotstring abbreviation
                }
                else if child is Map {
                    stack.Push(Array(string . char, child))
                }
            }
        }
        return match_list
    }
}