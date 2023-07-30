#Requires AutoHotkey v2.0-a
CoordMode "Caret"

If (A_ScriptFullPath = A_LineFile) {
    ; Objects
    completion_menu := SuggestionsGui()
    add_word_menu := AddWordGui()
    Global gathered_input := InputHook("C V", "")

    ; Bound actions
    gathered_input.NotifyNonText := True
    gathered_input.OnChar := ObjBindMethod(completion_menu, "CharUpdateInput")
    gathered_input.OnKeyUp := ObjBindMethod(completion_menu, "AltUpdateInput")
    gathered_input.OnEnd := ObjBindMethod(completion_menu, "ResetWord")
    gathered_input.Start()

    ; Hotkeys
    HotIf
    Hotkey "~LButton", key => completion_menu.ResetWord("Mouse")
    Hotkey "~MButton", key => completion_menu.ResetWord("Mouse")
    Hotkey "~RButton", key => completion_menu.ResetWord("Mouse")
    Hotkey completion_menu.settings["add_word"], key => add_word_menu.ShowGui()
    Hotkey "#F", key => completion_menu.diagnose()

    HotIfWinExist "Completion Menu"
    Hotkey "~LButton", key => completion_menu.CheckClickLocation()
    Hotkey completion_menu.settings["insert_hotkey"], key => completion_menu.KeyboardInsertMatch()
    Hotkey completion_menu.settings["next_item"], key => completion_menu.ChangeFocus("Down")
    Hotkey completion_menu.settings["previous_item"], key => completion_menu.ChangeFocus("Up")
    Hotkey completion_menu.settings["hide_menu"], key => completion_menu.ResetGui()

    HotIf

    CustomizeTrayMenu()
}

FindActivePos() {
    if WinExist("A") {
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

; Escapes special character from raw string
AddEscapeSequences(string) {
    string := StrReplace(string, "``", "````")
    string := StrReplace(string, "`r`n", "``n")
    string := StrReplace(string, "`n", "``n")
    string := StrReplace(string, "`t", "``t")
    string := StrReplace(string, "`;", "```;")
    return string
}

; Changes escape sequences in the string to the special character itself for sending
; Thanks to Kisang Kim
InvertEscapeSequences(string) {
    string := StrReplace(string, "````", "``")
    string := StrReplace(string, "```;", "`;")
    string := StrReplace(string, "```:", "`:")
    string := StrReplace(string, "``n", "`n")
    string := StrReplace(string, "``r", "`n")
    string := StrReplace(string, "``t", "`t")
    string := StrReplace(string, "``b", "`b")
    string := StrReplace(string, "``s", "`s")
    string := StrReplace(string, "``v", "`v")
    string := StrReplace(string, "``a", "`a")
    string := StrReplace(string, "``f", "`f")
    string := StrReplace(string, "```"", "`"")
    string := StrReplace(string, "```'", "`'")
    Return string
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
        this.settings["filtered_applications"] := StrSplit(this.settings["filtered_applications"], ",")
        if this.settings["filter_type"] == "whitelist" {
          this.ShouldShowMenu := this.IsFilteredApp
        }
        else {
          this.ShouldShowMenu := this.IsntFilteredApp
        }

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
            if this.settings["run_files"] {
                Run path
            }
            index += 3
        }

        word_list_files := StrSplit(this.settings.Get("word_list_files", ""), ",")
        for file in word_list_files {
            this.LoadWordFile(file)
        }

        ; State
        this.search_stack := Array("", this.word_list.root) ; array isn't as nice as map but keeps oldest strings at the front
    }

    ResetGui() {
        this.window.Destroy()
        this.window := this.MakeGui()
        this.matches := this.MakeLV(this.settings["bg_colour"], this.settings["text_colour"])
    }

    MakeGui() {
        window := Gui("+AlwaysOnTop +ToolWindow -Caption", "Completion Menu", this)
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

    IsFilteredApp() {
        for app in this.settings["filtered_applications"] {
            if WinActive(app) {
                return True
            }
        }
        return False
    }

    IsntFilteredApp() {
        return not this.IsFilteredApp()
    }

    LoadWordFile(word_file) {
        Loop read, word_file {
            this.LoadWord(A_LoopReadLine)
        }
    }

    LoadHotstringFile(hotstring_file, load_word, load_trigger) {
        ; complexity is for handling continuation sections and hotstring options
        continuation := Map("is_active", False
                        ,"word", ""
                        ,"trigger", ""
                        ,"options", "")

        Loop read, hotstring_file {
            if continuation["is_active"] {
                trimmed_line := StrLower(Trim(A_LoopReadLine))
                if not continuation["word"] and trimmed_line != "(" {
                    continuation["is_active"] := False
                    continue
                }
                else if trimmed_line = ")" {
                    this.LoadHotstring(continuation["options"], continuation["word"], continuation["trigger"], load_word, load_trigger)
                    continuation["is_active"] := False
                }
                else {
                    continuation["word"] := continuation["word"] = "`n(" ? A_LoopReadLine : continuation["word"] . "`n" . A_LoopReadLine
                }
                continue
            }

            is_hotstring := RegExMatch(A_LoopReadLine, ":(?P<Options>.*?):(?P<Abbreviation>.*?)::(?P<Replacement>.*)", &hotstring_part)
            if not is_hotstring or not hotstring_part.Abbreviation {
                continue
            }
            if not hotstring_part.Replacement {
                continuation["is_active"] := True
                continuation["word"] := ""
                continuation["trigger"] := hotstring_part.Abbreviation
                continuation["options"] := hotstring_part.Options
                continue
            }
            this.LoadHotstring(hotstring_part.Options, hotstring_part.Replacement, hotstring_part.Abbreviation, load_word, load_trigger)
        }
    }

    LoadWord(word) {
        if StrLen(word) >= this.settings["min_suggestion_length"] {
            this.word_list.Insert(word)
            this.word_list.Insert(StrUpper(SubStr(word, 1, 1)) . SubStr(word, 2))
        }
    }

    LoadHotstring(options, word, trigger, load_word, load_trigger) {
        if StrLen(word) < this.settings["min_suggestion_length"] or options ~= "i)\A(\?|X)\z" {
            return
        }
        case_sensitive := InStr(options, "C") ? True : False
        if not case_sensitive {
            upper_word := StrUpper(SubStr(word, 1, 1)) . SubStr(word, 2)
            upper_trigger := StrUpper(SubStr(trigger, 1, 1)) . SubStr(trigger, 2)
        }
        if load_word {
            this.word_list.Insert(word, trigger, "is_word")
            if not case_sensitive {
                this.word_list.Insert(upper_word, upper_trigger, "is_word")
            }
        }
        if load_trigger {
            this.word_list.Insert(trigger, word, "is_hotstring")
            if not case_sensitive {
                this.word_list.Insert(upper_trigger, upper_word, "is_hotstring")
            }
        }
    }

    InsertMatch(matches, row) {
        word := matches.GetText(row, 2)
        hotstring := matches.GetText(row, 1)
        send_str := ""
        index := 1
        ; find the matching prefix in the search stack and remove that many characters from the input
        while index <= this.search_stack.Length {
            prefix := this.search_stack[index]
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
            index += 2
        }
        this.ResetWord("insert")
        if send_str {
            gathered_input.OnChar := ""
            Send InvertEscapeSequences(send_str)
            Send this.settings["end_char"]
            SendLevel 1 ; to reset hotstrings in other scripts
            Send "{Left}{Right}"
            SendLevel 0
            gathered_input.OnChar := ObjBindMethod(completion_menu, "CharUpdateInput")
        }
        ; else {
            ; could add new hotkey from here. it would trigger whenever you double clicked an empty row with -readonly in gui.
        ; }
        return
    }

    KeyboardInsertMatch(*) {
        focused := ListViewGetContent("Count Focused", this.matches)
        if not focused {
            focused := 1
        }
        this.InsertMatch(this.matches, focused)
        return
    }

    ChangeFocus(direction, *) {
        focused := ListViewGetContent("Count Focused", this.matches)
        if not focused {
            this.matches.Modify(1, "+Select +Focus +Vis")
            return
        }
        else {
            this.matches.Modify(focused, "-Select -Focus -Vis")
        }

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
        if not this.ShouldShowMenu() {
            return
        }

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

        ; whitespace and enter adds new word to search_stack
        if key = " " or key = "`n" or key = Chr(0x9) { ; Chr(0x9) = "Tab"
            this.search_stack.Push("", this.word_list.root)
        }

        this.UpdateSuggestions()
    }

    AltUpdateInput(hook, params*) {
        if not this.ShouldShowMenu() {
            return
        }

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

            if prefix = "" or StrLen(prefix) < this.settings["min_show_length"] {
                continue
            }

            hotstring_matches.Push(this.FindMatches(prefix, node, "is_hotstring", this.settings["exact_match_hotstring"])*)
            word_matches.Push(this.FindMatches(prefix, node, "is_word", this.settings["exact_match_word"])*)
        }

        this.AddMatchControls(hotstring_matches, word_matches)
        if this.matches.GetCount() {
            this.matches.Modify(1, "+Select +Focus +Vis")
            sleep 10 ; to update caret position
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
            if this.matches.GetCount() >= this.settings["max_rows"] { ; big optimization but could improve selection rather than hotstrings always getting priority
                break
            }
            this.matches.Add(, match[1], match[2])
        }
        for match in word_matches {
            if this.matches.GetCount() >= this.settings["max_rows"] {
                break
            }
            this.matches.Add(, match[1], match[2])
        }

        this.matches.ModifyCol(1, "AutoSize")
        this.matches.ModifyCol(2, "AutoHdr")
        this.matches.Opt("+Redraw")
    }

    ResizeGui(){
        this.shown_rows := min(this.settings["max_visible_rows"], this.matches.GetCount())

        this.window.Move(,, this.settings["gui_width"] - this.settings["scrollbar_width"], this.shown_rows * this.settings["row_height"])
    }

    ShowGui(){
        if this.settings["try_caret"] and CaretGetPos(&x, &y) {
            this.window.Show("x" x " y" y + this.settings["caret_offset"] " NoActivate")
        }
        else {
            pos := FindActivePos()
            this.window.Show("x" pos[1] - this.settings["x_window_offset"] " y" pos[2] - 10 - this.shown_rows * this.settings["y_window_offset"] " NoActivate")
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

    ; returns list of word list and hotstring files for the insertion menu
    GetFileOptions() {
        options := StrSplit(this.settings.Get("word_list_files", ""), ",")
        hotstring_files := StrSplit(this.settings.Get("hotstring_files", ""), ",")
        index := 1
        while index < hotstring_files.Length {
            options.Push(hotstring_files[index])
            index += 3
        }
        return options
    }

    diagnose() {
        this.window.GetPos(&X, &Y, &Width, &Height)
        exists := WinExist("Completion Menu") != 0
        msgbox "Window Shown: " exists "`n" "Visible Control: " this.matches.Visible "`n" "Matches: " this.matches.GetCount() "`n" "Gui Position: X: " X ", Y: " Y ", Width: " Width ", Height: " Height
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

    Delete(prefix, id_key) {
        ; could optimize to remove obsolete branches but this is easier to implement
        node := this.FindNode(prefix)
        if node is Map and node.Has(id_key) {
            node.Delete(id_key)
            return True
        }
        return False
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

Class AddWordGui 
{
    __New() {
        this.file_options := completion_menu.GetFileOptions()
        this.input_gui := this.MakeGui()
    }

    MakeGui() {
        new_gui := Gui(, "Add New Match", this)
        new_gui.OnEvent("Escape", "HideGui")
        new_gui.SetFont("S" completion_menu.settings["font_size"], completion_menu.settings["font"])
        new_gui.Add("Text",,"Input the new hotstring or phrase:")
        this.input := new_gui.Add("Edit", "w250")
        this.selected_file := new_gui.Add("DropDownList", "w250", this.file_options)
        Enter := new_gui.Add("Button", "Default", "Enter")
        Enter.OnEvent("Click", "SubmitNewWord")
        Cancel := new_gui.Add("Button", "x+m", "Cancel")
        Cancel.OnEvent("Click", "HideGui")
        return new_gui
    }

    ShowGui() {
        selected_text := this.GetSelectedText()
        if selected_text {
            this.input.Text := selected_text
        }
        this.input_gui.Show("w300")
        WinWait "Add New Match"
        Send "{End}"
    }

    GetSelectedText() {
        ; from hotstring helper in docs
        old_contents := A_Clipboard
        A_Clipboard := ""
        Send "^{Ins}"
        Sleep 50
        selected_text := AddEscapeSequences(A_Clipboard)
        A_Clipboard := old_contents
        return selected_text
    }

    HideGui(*) {
        this.input_gui.Destroy()
        this.input_gui := this.MakeGui()
    }

    SubmitNewWord(*) {
        is_hotstring := RegExMatch(this.input.Text, "(?P<Label>:(?P<Options>.*?):(?P<Abbreviation>.*?))::(?P<Replacement>.*)", &Entered)
        if is_hotstring and (Entered.Abbreviation and Entered.Replacement) {
            completion_menu.LoadHotstring(Entered.Options, Entered.Replacement, Entered.Abbreviation, 1, 1)
            Hotstring Entered.Label, Entered.Replacement
        }
        else if StrLower(SubStr(this.selected_file.Text, -3)) == "ahk" {
            msgbox "Couldn't add new word. Make sure hotstrings are entered with correct AHK syntax eg '::btw::by the way'."
            return
        }
        else {
            completion_menu.LoadWord(this.input.Text)
        }

        if this.selected_file.Text {
            FileAppend "`n" this.input.Text, this.selected_file.Text
        }
        this.HideGui()
    }

}
