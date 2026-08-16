-- Emits: noteIndex <tab> relPath <tab> title <tab> attachmentCount <tab> attachmentNames
-- Numbering matches extract.applescript exactly (same folders.tsv order).

on run argv
	set stagingDir to item 1 of argv
	set folderSpec to my readFile(stagingDir & "/folders.tsv")

	set AppleScript's text item delimiters to linefeed
	set specLines to text items of folderSpec
	set AppleScript's text item delimiters to ""

	set outLines to {}
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
					set nt to note i of folder id fid
					set noteTitle to name of nt
					set ac to count of attachments of nt
					set nameList to {}
					repeat with a in attachments of nt
						try
							set end of nameList to (name of a)
						on error
							set end of nameList to "?"
						end try
					end repeat
				end tell
				set AppleScript's text item delimiters to ";"
				set namesText to nameList as text
				set AppleScript's text item delimiters to ""
				set end of outLines to idStr & tab & relPath & tab & noteTitle & tab & (ac as text) & tab & namesText
			end repeat
		end if
	end repeat

	set AppleScript's text item delimiters to linefeed
	set outText to outLines as text
	set AppleScript's text item delimiters to ""
	my writeFile(stagingDir & "/attachments.tsv", outText)
	return (counter as text) & " notes surveyed"
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
