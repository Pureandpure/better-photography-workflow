on run argv
    if (count of argv) is not 19 then error "Expected 19 arguments"

    set reminderListName to item 1 of argv
    set projectPath to item 2 of argv
    set projectEpoch to (item 3 of argv) as integer
    set reminderHour to (item 4 of argv) as integer
    set reminderMinute to (item 5 of argv) as integer
    set projectID to item 18 of argv
    set originalPath to item 19 of argv
    set createdCount to 0
    set skippedCount to 0

    tell application "Reminders"
        if not (exists list reminderListName) then
            set targetList to make new list with properties {name:reminderListName}
        else
            set targetList to list reminderListName
        end if

        repeat with taskIndex from 0 to 3
            set argumentOffset to 6 + (taskIndex * 3)
            set taskName to item argumentOffset of argv
            set taskDays to (item (argumentOffset + 1) of argv) as integer
            set taskDescription to item (argumentOffset + 2) of argv
            set projectName to my basenameOfPath(projectPath)
            set taskTitle to "【" & projectName & "】" & taskName
            set taskBody to "摄影项目路径：" & projectPath & return & "任务说明：" & taskDescription & return & "来源：better-photography-workflow" & return & "BPW Project ID：" & projectID & return

            set isDuplicate to false
            set sameNameReminders to every reminder of targetList whose name ends with taskName
            repeat with existingReminder in sameNameReminders
                try
                    if ((body of existingReminder as text) contains ("BPW Project ID：" & projectID & return) or (body of existingReminder as text) contains ("摄影项目路径：" & originalPath & return)) and (body of existingReminder as text) contains "来源：better-photography-workflow" then
                        set isDuplicate to true
                        exit repeat
                    end if
                end try
            end repeat

            if isDuplicate then
                set skippedCount to skippedCount + 1
            else
                set currentEpoch to (do shell script "/bin/date +%s") as integer
                set dueDate to (current date) + (projectEpoch - currentEpoch)
                set time of dueDate to (reminderHour * hours) + (reminderMinute * minutes)
                set day of dueDate to (day of dueDate) + taskDays
                make new reminder at end of reminders of targetList with properties {name:taskTitle, body:taskBody, due date:dueDate}
                set createdCount to createdCount + 1
            end if
        end repeat
    end tell

    return "created=" & createdCount & " skipped=" & skippedCount
end run

on basenameOfPath(posixPath)
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "/"
    set pathParts to text items of posixPath
    set AppleScript's text item delimiters to oldDelimiters
    return item -1 of pathParts
end basenameOfPath
