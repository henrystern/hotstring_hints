#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; this branch searches across multiple prefixes rather than just keeping one word as the prefix. It is fairly resource intensive when typing quickly

; todos
; read multi line hotstrings maybe a hover tooltip to see entire output
; better hotstring modification and implement adding hotstrings
; add stack for multi word hotstrings
; allow loading multiple hotkey files - with individual options
; optimize -- store last Trie root and go from there if just a char addition

^r::Reload ; for development
Ins::show_searches

If (A_ScriptFullPath = A_LineFile) {
    ; Objects
    completion_menu := SuggestionsGui()
    Global gathered_input := InputHook("C V", "")

    ; Bound actions
    reset := ObjBindMethod(completion_menu, "ResetWord")
    check_click := ObjBindMethod(completion_menu, "CheckClickLocation")
    insert_match := ObjBindMethod(completion_menu, "KeyboardInsertMatch")
    change_focus_down := ObjBindMethod(completion_menu, "ChangeFocus", "Down")
    change_focus_up := ObjBindMethod(completion_menu, "ChangeFocus", "Up")

    gathered_input.OnChar := ObjBindMethod(completion_menu, "CharUpdateInput")
    gathered_input.NotifyNonText := True
    gathered_input.OnKeyUp := ObjBindMethod(completion_menu, "AltUpdateInput")
    gathered_input.OnEnd := reset
    gathered_input.Start()

    ; Hotkeys
    HotIf
    Hotkey "~SC03A & ~SC027", reset
    Hotkey "~LButton", reset
    Hotkey "~MButton", reset
    Hotkey "~RButton", reset

    HotIfWinExist "Completion Menu"
    Hotkey "~LButton", check_click
    Hotkey "^Space", insert_match
    Hotkey "Tab", change_focus_down
    Hotkey "+Tab", change_focus_up
    Hotkey "^k", reset

    HotIf
}

show_searches(*) {
    out := ""
    for prefix, _ in completion_menu.search_stack {
        out .= prefix "`n"
    }
    msgbox out
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


Class SuggestionsGui
{
    __New() {
        ; settings
        this.hotstring_file := A_ScriptDir "/expansions.ahk"
        this.max_rows := 10
        this.min_show_length := 2
        this.min_suggestion_length := 4
        this.bg_colour := "2B2A33"
        this.text_colour := "C9C5A2"
        this.try_caret := True ; try to show gui under caret - will only work in some apps
        this.exact_match_word := False
        this.exact_match_hotstring := True
        this.load_hotstring_words := True
        this.load_hotstring_triggers := True


        this.suggestions := this.MakeGui()
        this.matches := this.MakeLV()

        ; Load wordlist
        this.word_list := TrieNode()
        this.LoadHotstringFile(this.hotstring_file)

        ; State
        this.search_stack := Map("", this.word_list.root)
    }

    MakeGui() {
        suggestions := Gui("+AlwaysOnTop +ToolWindow -Caption", "Completion Menu", this)
        suggestions.MarginX := 0
        suggestions.MarginY := 0
        suggestions.SetFont("S10", "Verdana")
        return suggestions
    }

    MakeLV() {
        matches := this.suggestions.Add("ListView", "r" this.max_rows " w200 +Grid -Multi -ReadOnly -Hdr +Background" this.bg_colour " +C" this.text_colour " -E0x200", ["Abbr.", "Word"]) ; E0x200 hides border
        matches.OnEvent("DoubleClick", "InsertMatch")
        matches.OnEvent("ItemEdit", "ModifyHotstring")

        this.suggestions.Show("Hide") ; makes gui resizable to correct number of rows on first suggestion
        return matches
    }

    LoadWordFile(word_file) {
        Loop read, word_file {
            this.LoadWord(A_LoopReadLine)
        }
    }

    LoadHotstringFile(hotstring_file) {
        Loop read, hotstring_file {
            first_two := SubStr(A_LoopReadLine, 1, 2)
            if first_two = "::" {
                this.LoadHotstring(A_LoopReadLine)
            }
            else {
                continue
            }
        }
    }

    LoadWord(word) {
        if StrLen(word) >= this.min_suggestion_length {
            this.word_list.Insert(A_LoopReadLine)
        }
    }

    LoadHotstring(hstring) {
        split := StrSplit(hstring, "::")
        trigger := split[2]
        word := split[3]
        if StrLen(word) >= this.min_suggestion_length {
            if this.load_hotstring_words {
                this.word_list.Insert(word, trigger, "is_word")
            }
            if this.load_hotstring_triggers {
                this.word_list.Insert(trigger, word, "is_hotstring")
            }
        }
    }

    InsertMatch(matches, row) {
        prefix := gathered_input.Input
        prefix_length := StrLen(prefix)
        word := matches.GetText(row, 2)
        this.ResetWord("Insert")
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
        focused := ListViewGetContent("Count Focused", this.matches)
        this.InsertMatch(this.matches, focused)
        return
    }

    ChangeFocus(direction, *) {
        focused := ListViewGetContent("Count Focused", this.matches)
        if direction = "Up" and this.match_rows {
            this.matches.Modify(Mod(focused - 1, this.match_rows), "+Select +Focus")
        }
        else if direction = "Down" and this.match_rows {
            this.matches.Modify(Mod(focused + 1, this.match_rows), "+Select +Focus")
        }
        return
    }

    ModifyHotstring(matches, row) {
        trigger := this.matches.GetText(row, 1)
        word := this.matches.GetText(row, 2)
        FileAppend "`r`n::" trigger "::" word, this.hotstring_file
        if this.load_hotstring_words {
            this.word_list.Insert(word, trigger, "is_word")
        }
        if this.load_hotstring_triggers {
            this.word_list.Insert(trigger, word, "is_hotstring")
        }
        Run this.hotstring_file
    }

    ResetWord(called_by) {
        if called_by is String { ; if not inputhook calling itself
            gathered_input.Stop()
        }

        this.suggestions.hide()
        this.matches.Delete()
        this.search_stack := Map("", this.word_list.root)
        gathered_input.Start()
        return
    }

    CharUpdateInput(hook, params*) {
        if params[1] = Chr(0x1B) { ; Chr(0x1B) = "Esc", Chr(0x9) = "Tab"
            ; tooltip "reset by " params[1]
            this.ResetWord("End_Key")
            return
        }

        ; tooltip "add " params[1]
        old_search_stack := this.search_stack.Clone()
        for prefix, node in old_search_stack {
            this.search_stack.Delete(prefix)
            new_prefix := prefix . params[1]
            ; tooltip "delete " prefix ", add " new_prefix
            if node.Has(params[1]) {
                this.search_stack[new_prefix] := node[params[1]]
            }
        }

        if params[1] = " " or params[1] = "`n" or params[1] = Chr(0x9) { ; Chr(0x9) = "Tab"
            ; tooltip "add new word " params[1]
            this.search_stack[""] := this.word_list.root
        }

        this.UpdateSuggestions()
    }

    AltUpdateInput(hook, params*) {
        key := GetKeyName(Format("vk{:x}sc{:x}", params[1], params[2]))
        if key = "Backspace" {
            old_search_stack := this.search_stack.Clone()
            for prefix, node in old_search_stack {
                this.search_stack.Delete(prefix)
                new_prefix := SubStr(prefix, 1, -1)
                this.search_stack[new_prefix] := this.word_list.FindNode(new_prefix)
            }
            this.UpdateSuggestions()
        }
        else if (key = "LShift" or key = "RShift" or key = "LControl" or key = "RControl" or key = "Capslock") {
            ; tooltip "ignored " key
        }
        else {
            ; tooltip "reset by " key
            this.ResetWord("End_Key")
        }
    }

    UpdateSuggestions() {
        if WinActive("Completion Menu") {
            return
        } 

        hotstring_matches := []
        word_matches := []

        for prefix, node in this.search_stack {
            if StrLen(prefix) < this.min_show_length {
                continue
            }

            if this.load_hotstring_triggers {
                hotstring_matches.Push(this.FindMatches(prefix, node, "is_hotstring", this.exact_match_hotstring)*)
            }
            if this.load_hotstring_words {
                word_matches.Push(this.FindMatches(prefix, node, "is_word", this.exact_match_word)*)
            }
        }

        if not (hotstring_matches or word_matches) {
            this.suggestions.hide()
        }
        else {
            this.AddMatchControls(hotstring_matches, word_matches)
            this.ResizeGui()
            this.ShowGui()
        }
    }

    AddMatchControls(hotstring_matches, word_matches) {
        this.matches.Delete()
        this.match_rows := 0
        for match in hotstring_matches {
            this.matches.Add(, match[1], match[2])
            this.match_rows += 1
        }
        for match in word_matches {
            this.matches.Add(, match[1], match[2])
            this.match_rows += 1
        }

        this.matches.Modify(1, "+Select +Focus")
        this.matches.ModifyCol()
        this.matches.ModifyCol(2, "AutoHdr")
    }

    ResizeGui(){
        this.shown_rows := min(this.max_rows, this.match_rows)
        this.suggestions.Move(,,,this.shown_rows * 20) ; will have to change if font size changes
    }

    ShowGui(){
        if this.try_caret and CaretGetPos(&x, &y) {
            this.suggestions.Show("x" x " y" y + 20 " NoActivate")
        }
        else {
            pos := FindActivePos()
            this.suggestions.Show("x" pos[1] - 200 " y" pos[2] - 10 - this.shown_rows * 20 " NoActivate")
        }
    }

    FindMatches(current_word, current_node, match_key, exact_match) {
        if exact_match {
            return this.word_list.MatchWord(current_word, current_node, match_key)
        }
        else {
            return this.word_list.MatchPrefix(current_word, current_node, match_key)
        }
    }

    CheckClickLocation(*) {
        MouseGetPos ,, &clicked_window
        if not WinGetTitle(clicked_window) = "Completion Menu" {
            this.ResetWord("Click")
        }
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
                    match_list.Push(Array(child, string))
                }
                else if child is Map {
                    stack.Push(Array(string . char, child))
                }
            }
        }
        return match_list
    }
}