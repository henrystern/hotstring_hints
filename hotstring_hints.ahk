#Requires AutoHotkey v2.0-a
CoordMode "Caret"

; todos
; read multi line hotstrings maybe a hover tooltip to see entire output

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
    Hotkey "~LButton", reset
    Hotkey "~MButton", reset
    Hotkey "~RButton", reset

    HotIfWinExist "Completion Menu"
    Hotkey "~LButton", check_click
    Hotkey completion_menu.settings["insert_hotkey"], insert_match
    Hotkey completion_menu.settings["next_item"], change_focus_down
    Hotkey completion_menu.settings["previous_item"], change_focus_up
    Hotkey completion_menu.settings["hide_menu"], reset

    HotIf

    CustomizeTrayMenu()
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
    raw_settings := IniRead("settings.ini", settings_category,, False)
    if not raw_settings {
        raw_settings := IniRead("example_settings.ini", settings_category,, False)
    }
    if not raw_settings {
        msgbox "No settings.ini or example_settings.ini detected. Ensure a settings file is located in the script directory."
        ExitApp
    }
    settings := Map()
    Loop Parse, raw_settings, "`n"
    {
        Array := StrSplit(A_LoopField, "=")
        settings[Array[1]] := Trim(Array[2])
    }
    return settings 
}

CustomizeTrayMenu() {
    tray := A_TrayMenu
    tray.Delete
    tray.Add("Run on Startup", RunOnStartup)
    tray.Add()
    tray.Add("Open Script Folder", OpenScriptDir)
    tray.Add()
    tray.Add("Reload Script", ReloadScript)
    tray.Add("Exit", ExitScript )

    ; So that the startup shortcut will work even if the script has moved
    if FileExist(A_Startup "\hotstring_hints.lnk") {
        tray.Check("Run on Startup")
        FileCreateShortcut A_ScriptFullPath, A_Startup "\hotstring_hints.lnk"
    }

}

RunOnStartup(*) {
    tray := A_TrayMenu
    if FileExist(A_Startup "\hotstring_hints.lnk") {
        tray.Uncheck("Run on Startup")
        FileDelete A_Startup "\hotstring_hints.lnk"
    }
    else {
        tray.Check("Run on Startup")
        FileCreateShortcut A_ScriptFullPath, A_Startup "\hotstring_hints.lnk"
    }
}

OpenScriptDir(*) {
    Run A_ScriptDir
}

ReloadScript(*) {
    Reload
    Sleep 1000 ; If successful, the reload will close this instance during the Sleep, so the line below will never be reached.
    edit_script := MsgBox("The script could not be reloaded. Would you like to open it for editing?", "Reload Error")
}

ExitScript(*) {
    ExitApp
}

Class SuggestionsGui
{
    __New() {
        ; settings
        this.settings := ReadSettings("Settings")

        this.window := this.MakeGui()
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
            index += 3
        }

        word_list_files := StrSplit(this.settings.Get("word_list_files", ""), ",")
        for file in word_list_files {
            this.LoadWordFile(file)
        }

        ; State
        this.search_stack := Array("", this.word_list.root) ; array isn't as nice as map but keeps oldest strings at the front
    }

    MakeGui() {
        window := Gui("+AlwaysOnTop +ToolWindow -Caption -DPIScale", "Completion Menu", this)
        window.MarginX := 0
        window.MarginY := 0
        window.SetFont("S" this.settings["font_size"], this.settings["font"])
        return window
    }

    MakeLV(bg_colour, text_colour) {
        matches := this.window.Add("ListView", "r" this.settings["max_visible_rows"] " w" this.settings["gui_width"] " +Grid -Multi -Hdr +Background" bg_colour " +C" text_colour " -E0x200", ["Abbr.", "Word"]) ; E0x200 hides border
        matches.OnEvent("DoubleClick", "InsertMatch")
        matches.OnEvent("ItemEdit", "ModifyHotstring")
        this.window.Show("Hide") ; makes gui resizable to correct number of rows on first suggestion
        return matches
    }

    LoadWordFile(word_file) {
        Loop read, word_file {
            this.LoadWord(A_LoopReadLine)
        }
    }

    LoadHotstringFile(hotstring_file, load_word, load_trigger) {
        if load_word { ; saves trying to match if there are none loaded
            this.loaded_words := True
        }
        if load_trigger {
            this.loaded_triggers := True
        }
        Loop read, hotstring_file {
            first_two := SubStr(A_LoopReadLine, 1, 2)
            if first_two = "::" { ; could expand to include other hotstring styles with minor adjustments
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
        index := 1
        while index <= this.search_stack.Length {
            prefix := this.search_stack[index]
            prefix_length := StrLen(prefix)
            if not prefix {
                continue
            }
            ; find the matching prefix in the search stack and remove that many characters from the input
            else if SubStr(hotstring, 1, prefix_length) = prefix {
                send_str := "{Backspace " prefix_length "}" word
                break
            }  
            else if SubStr(word, 1, prefix_length) = prefix {
                send_str := SubStr(word, prefix_length + 1)
                break
            }
            index += 2
        }
        this.window.Hide()
        if send_str {
            SendLevel 1 ; to reset hotstrings in other scripts
            Send send_str
            SendLevel 0
            Send this.settings["end_char"]
        }
        ; else {
            ; could add new hotkey from here. it would trigger whenever you double clicked an empty row with -readonly in gui.
        ; }
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
        this.window.Hide()
        this.matches.Delete()
        this.search_stack := Array("", this.word_list.root)
        gathered_input.Start()
        return
    }

    CharUpdateInput(hook, params*) {
        key := params[1]
        if key = Chr(0x1B) or GetKeyState("Capslock", "P") { ; Chr(0x1B) = "Esc", Capslock is for compatibility with https://github.com/henrystern/extend_layer
            this.ResetWord("End_Key")
            return
        }

        ; Update the items in the stack with the new character. Deletes items with no more matching branches.
        index := 1
        while index <= this.search_stack.Length {
            if this.search_stack[index + 1].Has(key) {
                this.search_stack[index] := this.search_stack[index] . key
                this.search_stack[index + 1] := this.search_stack[index+1][key]
                index += 2
            }
            else {
                this.search_stack.RemoveAt(index, 2)
            }
        }

        if key = " " or key = "`n" or key = Chr(0x9) { ; Chr(0x9) = "Tab"
            this.search_stack.Push("", this.word_list.root)
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

            ; removes the last character from each string in the search stack and resets the node
            index := 1
            while index <= this.search_stack.Length {
                prefix := this.search_stack[index]
                if StrLen(prefix) > 1 {
                    new_prefix := SubStr(prefix, 1, -1)
                    this.search_stack[index] := new_prefix
                    this.search_stack[index + 1] := this.word_list.FindNode(new_prefix)
                }
                index += 2
            }
            this.UpdateSuggestions()
        }
        else if (key = "LShift" or key = "RShift" or key = "LControl" or key = "RControl" or key = "Capslock") {
            ; ignored keypresses - non alpha modified presses (eg ctrl+s) will still trigger ResetWord through the modified "s"
        }
        else {
            this.ResetWord("End_Key")
        }
    }

    UpdateSuggestions() {
        if WinActive("Completion Menu") {
            return
        } 

        hotstring_matches := []
        word_matches := []

        index := 1
        while index <= this.search_stack.Length {
            prefix := this.search_stack[index]
            node := this.search_stack[index + 1]
            index += 2

            if StrLen(prefix) < this.settings["min_show_length"] {
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
            this.window.hide()
        }
    }

    AddMatchControls(hotstring_matches, word_matches) {
        this.matches.Opt("-Redraw")
        this.matches.Delete()
        for match in hotstring_matches {
            if this.matches.GetCount() > this.settings["max_rows"] { ; big optimization but could improve selection rather than hotstrings always getting priority
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
        this.matches.ModifyCol(1, "AutoSize")
        this.matches.ModifyCol(2, "AutoHdr")
        this.matches.Opt("+Redraw")
    }

    ResizeGui(){
        this.shown_rows := min(this.settings["max_visible_rows"], this.matches.GetCount())

        this.window.Move(,, this.settings["gui_width"] - this.settings["scrollbar_width"], this.shown_rows * this.settings["row_height"]) ; font dependent, width hides scrollbar
    }

    ShowGui(){
        if this.settings["try_caret"] and CaretGetPos(&x, &y) {
            this.window.Show("x" x " y" y + this.settings["caret_offset"] " NoActivate")
        }
        else {
            pos := FindActivePos()
            this.window.Show("x" pos[1] - this.settings["gui_width"] " y" pos[2] - 10 - this.shown_rows * this.settings["row_height"] " NoActivate")
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

        Loop Parse, word {
            char := A_LoopField
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
            if match_key = "is_hotstring" {
                match_list.InsertAt(1, Array(word, root[match_key]))
            }
            else {
                match_list.InsertAt(1, Array(root[match_key], word))
            }
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
                    if match_key = "is_hotstring" {
                        match_list.InsertAt(1, Array(string, child))
                    }
                    else {
                        match_list.InsertAt(1, Array(child, string))
                    }
                }
                else if child is Map {
                    stack.Push(Array(string . char, child))
                }
            }
        }
        return match_list
    }
}