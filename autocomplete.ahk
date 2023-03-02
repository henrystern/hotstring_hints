#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; todos
; read multi line hotstrings maybe a hover tooltip to see entire output
; order hints by length/score

^r::Reload ; for development

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

ReadSettings(settings_category) {
    raw_settings := IniRead("settings.ini", settings_category)
    settings := Map()
    Loop Parse, raw_settings, "`n"
    {
        Array := StrSplit(A_LoopField, "=")
        settings[Array[1]] := Trim(Array[2])
    }
    return settings 
}

Class SuggestionsGui
{
    __New() {
        ; settings
        this.settings := ReadSettings("Settings")

        this.suggestions := this.MakeGui()
        this.matches := this.MakeLV(this.settings["bg_colour"], this.settings["text_colour"])

        ; Load wordlist
        this.word_list := TrieNode()

        hotstring_files := StrSplit(this.settings.Get("hotstring_files", ""), ",")
        index := 1
        while index < hotstring_files.Length {
            path := hotstring_files[index]
            load_words := hotstring_files[index + 1]
            load_triggers := hotstring_files[index + 2]
            this.LoadHotstringFile(path, load_words, load_triggers)
            Run path
            index += 3
        }

        word_list_files := StrSplit(this.settings.Get("word_list_files", ""), ",")
        for file in word_list_files {
            this.LoadWordFile(file)
        }

        ; State
        this.search_stack := Map("", this.word_list.root)
    }

    MakeGui() {
        suggestions := Gui("+AlwaysOnTop +ToolWindow -Caption", "Completion Menu", this)
        suggestions.MarginX := 0
        suggestions.MarginY := 0
        suggestions.SetFont("S12", "sans-serif")
        return suggestions
    }

    MakeLV(bg_colour, text_colour) {
        matches := this.suggestions.Add("ListView", "r" this.settings["max_visible_rows"] " w200 +Grid -Multi -Hdr +Background" bg_colour " +C" text_colour " -E0x200", ["Abbr.", "Word"]) ; E0x200 hides border
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

    LoadHotstringFile(hotstring_file, load_word, load_trigger) {
        if load_word {
            this.loaded_words := True
        }
        if load_trigger {
            this.loaded_triggers := True
        }
        Loop read, hotstring_file {
            first_two := SubStr(A_LoopReadLine, 1, 2)
            if first_two = "::" {
                this.LoadHotstring(A_LoopReadLine, load_word, load_trigger)
            }
            else {
                continue
            }
        }
    }

    LoadWord(word) {
        if StrLen(word) >= this.settings["min_suggestion_length"] {
            this.word_list.Insert(A_LoopReadLine)
        }
    }

    LoadHotstring(hstring, load_word, load_trigger) {
        split := StrSplit(hstring, "::")
        trigger := split[2]
        word := split[3]
        if StrLen(word) >= this.settings["min_suggestion_length"] {
            if load_word {
                this.word_list.Insert(word, trigger, "is_word")
            }
            if load_trigger {
                this.word_list.Insert(trigger, word, "is_hotstring")
            }
        }
    }

    InsertMatch(matches, row) {
        word := matches.GetText(row, 2)
        hotstring := matches.GetText(row, 1)
        send_str := ""
        for prefix, _ in this.search_stack {
            prefix_length := StrLen(prefix)
            if not prefix {
                continue
            }
            else if SubStr(hotstring, 1, prefix_length) = prefix {
                send_str := "{Backspace " prefix_length "}" word
                break
            }  
            else if SubStr(word, 1, prefix_length) = prefix {
                send_str := SubStr(word, prefix_length + 1)
                break
            }
        }
        this.suggestions.Hide()
        if send_str {
            SendLevel 1 ; to reset hotstrings in other scripts
            Send send_str
            SendLevel 0
        }
        else {
            ; add new hotkey form
        }
        return
    }

    KeyboardInsertMatch(*) {
        focused := ListViewGetContent("Count Focused", this.matches)
        this.InsertMatch(this.matches, focused)
        return
    }

    ChangeFocus(direction, *) {
        focused := ListViewGetContent("Count Focused", this.matches)
        if direction = "Up" {
            new_focused := focused = 1 ? this.matches.GetCount() : focused - 1
        }
        else if direction = "Down" {
            new_focused := focused = this.matches.GetCount() ? 1 : focused + 1
        }
        else {
            return
        }
        this.matches.Modify(new_focused, "+Select +Focus +Vis")
        return
    }

    ResetWord(called_by) {
        if called_by is String { ; if not inputhook calling itself
            gathered_input.Stop()
        }
        this.suggestions.Hide()
        this.matches.Delete()
        this.search_stack := Map("", this.word_list.root)
        gathered_input.Start()
        return
    }

    CharUpdateInput(hook, params*) {
        key := params[1]
        if key = Chr(0x1B) { ; Chr(0x1B) = "Esc", Chr(0x9) = "Tab"
            ; tooltip "reset by " params[1]
            this.ResetWord("End_Key")
            return
        }

        ; tooltip "add " params[1]
        old_search_stack := this.search_stack.Clone()
        for prefix, node in old_search_stack {
            this.search_stack.Delete(prefix)
            new_prefix := prefix . key
            ; tooltip "delete " prefix ", add " new_prefix
            if node.Has(key) {
                this.search_stack[new_prefix] := node[key]
            }
        }

        if key = " " or key = "`n" or key = Chr(0x9) { ; Chr(0x9) = "Tab"
            ; tooltip "add new word " key
            this.search_stack[""] := this.word_list.root
        }

        this.UpdateSuggestions()
    }

    AltUpdateInput(hook, params*) {
        key := GetKeyName(Format("vk{:x}sc{:x}", params[1], params[2]))
        if key = "Backspace" {
            if GetKeyState("Control") {
                this.ResetWord("End_Key")
                return
            }

            old_search_stack := this.search_stack.Clone()
            for prefix, node in old_search_stack {
                this.search_stack.Delete(prefix)
                if StrLen(prefix) > 1 {
                    new_prefix := SubStr(prefix, 1, -1)
                    this.search_stack[new_prefix] := this.word_list.FindNode(new_prefix)
                }
                else {
                    this.search_stack[""] := this.word_list.root
                }
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
            if prefix = "" or StrLen(prefix) < this.settings["min_show_length"] {
                continue
            }

            if this.loaded_triggers {
                hotstring_matches.Push(this.FindMatches(prefix, node, "is_hotstring", this.settings["exact_match_hotstring"])*)
            }
            if this.loaded_words {
                word_matches.Push(this.FindMatches(prefix, node, "is_word", this.settings["exact_match_word"])*)
            }
        }

        this.AddMatchControls(hotstring_matches, word_matches)
        if this.matches.GetCount() {
            this.ResizeGui()
            this.ShowGui()
        }
        else {
            this.suggestions.hide()
        }
    }

    AddMatchControls(hotstring_matches, word_matches) {
        this.matches.Opt("-Redraw")
        this.matches.Delete()
        for match in hotstring_matches {
            if this.matches.GetCount() > this.settings["max_rows"] {
                break
            }
            this.matches.Add(, match[1], match[2])
        }
        for match in word_matches {
            if this.matches.GetCount() > this.settings["max_rows"] {
                break
            }
            this.matches.Add(, match[1], match[2])
        }

        this.matches.Modify(1, "+Select +Focus")
        this.matches.ModifyCol()
        this.matches.ModifyCol(2, "AutoHdr")
        this.matches.Opt("+Redraw")
    }

    ResizeGui(){
        this.shown_rows := min(this.settings["max_visible_rows"], this.matches.GetCount())

        this.suggestions.Move(,,180,this.shown_rows * 24) ; font dependent, width hides scrollbar
    }

    ShowGui(){
        static monitor_boundary := SysGet(78)
        if this.settings["try_caret"] and CaretGetPos(&x, &y) {
            this.suggestions.Show("x" x " y" y + 20 " NoActivate")
        }
        else {
            pos := FindActivePos()
            this.suggestions.Show("x" pos[1] - 190 " y" pos[2] - 10 - this.shown_rows * 24 " NoActivate")
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