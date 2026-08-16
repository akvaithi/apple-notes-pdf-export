-- Reads <staging>/folders.tsv (folderID <tab> relativePath), then writes each
-- note's HTML body to <staging>/html/NNNN.html plus a manifest TSV.
-- Everything is addressed by folder id inside each tell block, because folder
-- references go stale the moment they cross a tell/handler boundary.

on run argv
	set stagingDir to item 1 of argv
	set folderSpec to my readFile(stagingDir & "/folders.tsv")

	set AppleScript's text item delimiters to linefeed
	set specLines to text items of folderSpec
	set AppleScript's text item delimiters to ""

	set manifestLines to {}
	set counter to 0

	repeat with specLine in specLines
		if (length of specLine) > 0 then
			set AppleScript's text item delimiters to tab
			set parts to text items of specLine
			set AppleScript's text item delimiters to ""
			set fid to item 1 of parts
			set relPath to item 2 of parts

			tell application "Notes"
				set noteCount to count of notes of folder id fid
			end tell

			repeat with i from 1 to noteCount
				set counter to counter + 1
				set idStr to my pad(counter)
				tell application "Notes"
					set noteTitle to name of note i of folder id fid
					set noteBody to body of note i of folder id fid
					set noteMod to (modification date of note i of folder id fid) as text
					set noteID to id of note i of folder id fid
				end tell
				my writeFile(stagingDir & "/html/" & idStr & ".html", noteBody)
				set end of manifestLines to idStr & tab & relPath & tab & noteTitle & tab & noteMod & tab & noteID
			end repeat

			log relPath & " -> " & noteCount
		end if
	end repeat

	set AppleScript's text item delimiters to linefeed
	set manifestText to manifestLines as text
	set AppleScript's text item delimiters to ""
	my writeFile(stagingDir & "/manifest.tsv", manifestText)
	return (counter as text) & " notes extracted"
end run

on pad(n)
	set s to n as text
	repeat while length of s < 4
		set s to "0" & s
	end repeat
	return s
end pad

on readFile(pathStr)
	return (read (POSIX file pathStr) as «class utf8»)
end readFile

on writeFile(pathStr, txt)
	set fh to open for access (POSIX file pathStr) with write permission
	set eof fh to 0
	write txt to fh as «class utf8»
	close access fh
end writeFile
