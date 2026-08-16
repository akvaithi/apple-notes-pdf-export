-- Drives Notes' own File > Export To > PDF for the notes whose local fallback
-- render is too low-resolution to magnify. Output lands in <staging>/raw/<idx>.pdf.
--
-- The save panel remembers its directory between invocations, so the target
-- folder is only navigated to once.

on run argv
	set stagingDir to item 1 of argv
	set rawDir to stagingDir & "/raw"
	set spec to my readFile(stagingDir & "/hifi.tsv")

	set AppleScript's text item delimiters to linefeed
	set rows to text items of spec
	set AppleScript's text item delimiters to ""

	set navigated to false
	set doneCount to 0
	set failed to {}

	repeat with rowRef in rows
		set row to rowRef as text
		if (length of row) > 0 then
			set AppleScript's text item delimiters to tab
			set parts to text items of row
			set AppleScript's text item delimiters to ""
			set idx to item 1 of parts
			set noteID to item 2 of parts

			try
				tell application "Notes"
					activate
					show note id noteID
				end tell
				delay 1.1

				tell application "System Events" to tell process "Notes"
					click menu item "PDF" of menu 1 of menu item "Export To" of menu 1 of menu bar item "File" of menu bar 1
				end tell

				-- wait for the save sheet
				set sg to my waitForSavePanel(12)
				if sg is missing value then error "save panel never appeared"

				if not navigated then
					tell application "System Events" to tell process "Notes"
						keystroke "g" using {command down, shift down}
					end tell
					delay 1.4
					tell application "System Events" to keystroke rawDir
					delay 1.0
					tell application "System Events" to key code 36
					delay 1.4
					set navigated to true
					set sg to my waitForSavePanel(10)
				end if

				tell application "System Events" to tell process "Notes"
					set value of text field 2 of sg to (idx & ".pdf")
					delay 0.4
					click button "Save" of sg
				end tell

				-- wait for the sheet to close (export can take a few seconds)
				my waitForSheetGone(40)
				delay 0.3

				if my fileExists(rawDir & "/" & idx & ".pdf") then
					set doneCount to doneCount + 1
				else
					set end of failed to idx
				end if
			on error errm
				set end of failed to idx
				-- try to clear any stuck sheet before moving on
				try
					tell application "System Events" to key code 53
				end try
				delay 0.5
			end try
		end if
	end repeat

	set AppleScript's text item delimiters to ","
	set failText to failed as text
	set AppleScript's text item delimiters to ""
	return "exported " & doneCount & " failed:" & failText
end run

-- Returns the save panel's splitter group, or missing value on timeout.
-- Export uses a sheet on the window; some panels nest one level deeper.
on waitForSavePanel(timeoutSecs)
	set n to timeoutSecs * 4
	repeat n times
		try
			tell application "System Events" to tell process "Notes"
				if (count of sheets of window 1) > 0 then
					set sh to sheet 1 of window 1
					if (count of sheets of sh) > 0 then
						return splitter group 1 of sheet 1 of sh
					else
						return splitter group 1 of sh
					end if
				end if
			end tell
		end try
		delay 0.25
	end repeat
	return missing value
end waitForSavePanel

on waitForSheetGone(timeoutSecs)
	set n to timeoutSecs * 4
	repeat n times
		try
			tell application "System Events" to tell process "Notes"
				if (count of sheets of window 1) = 0 then return true
			end tell
		on error
			return true
		end try
		delay 0.25
	end repeat
	return false
end waitForSheetGone

on fileExists(p)
	try
		do shell script "test -s " & quoted form of p
		return true
	on error
		return false
	end try
end fileExists

on readFile(pathStr)
	return (read (POSIX file pathStr) as «class utf8»)
end readFile
