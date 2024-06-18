﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# ===================================================================================================
# FileNames
# ===================================================================================================
function Get-FileName {
    Write-Host -ForegroundColor Cyan "Creating FileName for $Identity..."

    $ThisMeetingID = $script:GCDO.CleanGlobalObjectId | Select-Object -Unique
    $ShortMeetingID = $ThisMeetingID.Substring($ThisMeetingID.length - 6)

    if ($script:Identity -like "*@*") {
        $script:ShortId = $script:Identity.Split('@')[0]
    } else {
        $script:ShortId = $script:Identity
    }
    $script:ShortId = $ShortId.Substring(0, [System.Math]::Min(20, $ShortId.Length))

    if (($null -eq $CaseNumber) -or
        ([string]::IsNullOrEmpty($CaseNumber))) {
        $Case = ""
    } else {
        $Case = $CaseNumber + "_"
    }

    if ($ExportToExcel.IsPresent) {
        $script:FileName = "$($Case)CalLogSummary_$($ShortMeetingID).xlsx"
        Write-Host -ForegroundColor Blue -NoNewline "All Calendar Logs for meetings ending in ID [$ShortMeetingID] will be saved to : "
        Write-Host -ForegroundColor Yellow "$Filename"
    } else {
        $script:Filename = "$($Case)$($ShortId)_$ShortMeetingID.csv"
        $script:FilenameRaw = "$($Case)$($ShortId)_RAW_$($ShortMeetingID).csv"
        $Script:TimeLineFilename = "$($Case)$($ShortId)_TimeLine_$ShortMeetingID.csv"

        Write-Host -ForegroundColor Cyan -NoNewline "Enhanced Calendar Logs for [$Identity] has been saved to : "
        Write-Host -ForegroundColor Yellow "$Filename"

        Write-Host -ForegroundColor Cyan -NoNewline "Raw Calendar Logs for [$Identity] has been saved to : "
        Write-Host -ForegroundColor Yellow "$FilenameRaw"

        Write-Host -ForegroundColor Cyan -NoNewline "TimeLine for [$Identity] has been saved to : "
        Write-Host -ForegroundColor Yellow "$TimeLineFilename"
    }
}

function Export-CalLog {
    Get-FileName

    if ($ExportToExcel.IsPresent) {
        Export-CalLogExcel
    } else {
        Export-CalLogCSV
    }
}

function Export-CalLogCSV {
    $GCDOResults | Export-Csv -Path $Filename -NoTypeInformation -Encoding UTF8
    $script:GCDO | Export-Csv -Path $FilenameRaw -NoTypeInformation -Encoding UTF8
}

# Export to Excel
function Export-CalLogExcel {
    Write-Host -ForegroundColor Cyan "Exporting Enhanced CalLogs to Excel Tab [$ShortId]..."
    $ExcelParamsArray = GetExcelParams -path $FileName -tabName $ShortId

    $excel = $GCDOResults | Export-Excel @ExcelParamsArray -PassThru

    FormatHeader ($excel)

    Export-Excel -ExcelPackage $excel -WorksheetName $ShortId -MoveToStart

    # Export Raw Logs for Developer Analysis
    Write-Host -ForegroundColor Cyan "Exporting Raw CalLogs to Excel Tab [$($ShortId + "_Raw")]..."
    $script:GCDO | Export-Excel -Path  $FileName -WorksheetName $($ShortId + "_Raw") -AutoFilter -FreezeTopRow -BoldTopRow -MoveToEnd
}

function Export-Timeline {
    Write-Verbose "Export to Excel is : $ExportToExcel"

    # Display Timeline to screen:
    Write-Host -ForegroundColor Cyan "Timeline for [$Identity]..."
    $script:TimeLineOutput

    if ($ExportToExcel.IsPresent) {
        Export-TimelineExcel
    } else {
        $script:TimeLineOutput | Export-Csv -Path $script:TimeLineFilename -NoTypeInformation -Encoding UTF8 -Append
    }
}

function Export-TimelineExcel {
    Write-Host -ForegroundColor Cyan "Exporting Timeline to Excel..."
    $script:TimeLineOutput | Export-Excel -Path $FileName -WorksheetName $($ShortId + "_TimeLine") -Title "Timeline for $Identity" -AutoSize -FreezeTopRow -BoldTopRow
}

function GetExcelParams($path, $tabName) {
    if ($script:IsOrganizer) {
        $TableStyle = "Light10" # Orange for Organizer
        $TitleExtra = ", Organizer"
    } elseif ($script:IsRoomMB) {
        Write-Host -ForegroundColor green "Room Mailbox Detected"
        $TableStyle = "Light11" # Green for Room Mailbox
        $TitleExtra = ", Resource"
    } else {
        $TableStyle = "Light12" # Light Blue for normal
        # Dark Blue for Delegates (once we can determine this)
    }

    return @{
        Path                    = $path
        FreezeTopRow            = $true
        #  BoldTopRow              = $true
        Verbose                 = $false
        TableStyle              = $TableStyle
        WorksheetName           = $tabName
        TableName               = $tabName
        FreezeTopRowFirstColumn = $true
        AutoFilter              = $true
        AutoNameRange           = $true
        Append                  = $true
        Title                   = "Enhanced Calendar Logs for $Identity" + $TitleExtra + " for MeetingID [$($script:GCDO[0].CleanGlobalObjectId)]."
        ConditionalText         = $ConditionalFormatting
    }
}

$ConditionalFormatting = $(
    # Client, ShortClientInfoString and ClientInfoString
    New-ConditionalText "Outlook" -ConditionalTextColor Green -BackgroundColor $null
    New-ConditionalText "OWA" -ConditionalTextColor DarkGreen -BackgroundColor $null
    New-ConditionalText "Transport" -ConditionalTextColor Blue -BackgroundColor $null
    New-ConditionalText "Repair" -ConditionalTextColor DarkRed -BackgroundColor LightPink
    New-ConditionalText "Other ?BA" -ConditionalTextColor Orange -BackgroundColor $null
    New-ConditionalText "Other REST" -ConditionalTextColor DarkRed -BackgroundColor $null
    New-ConditionalText "ResourceBookingAssistant" -ConditionalTextColor Blue -BackgroundColor $null

    #IsIgnorable
    New-ConditionalText -Range "C3:C9999" -ConditionalType ContainsText -Text "Ignorable" -ConditionalTextColor DarkRed -BackgroundColor $null
    New-ConditionalText -Range "C:C" -ConditionalType ContainsText -Text "Cleanup" -ConditionalTextColor DarkRed -BackgroundColor $null
    New-ConditionalText -Range "C:C" -ConditionalType ContainsText -Text "Sharing" -ConditionalTextColor Blue -BackgroundColor $null

    # TriggerAction
    New-ConditionalText -Range "H:H" -ConditionalType ContainsText -Text "Create" -ConditionalTextColor Green -BackgroundColor $null
    New-ConditionalText -Range "H:H" -ConditionalType ContainsText -Text "Delete" -ConditionalTextColor Red -BackgroundColor $null
    # ItemClass
    New-ConditionalText -Range "I:I" -ConditionalType ContainsText -Text "IPM.Appointment" -ConditionalTextColor Blue -BackgroundColor $null
    New-ConditionalText -Range "I:I" -ConditionalType ContainsText -Text "Canceled" -ConditionalTextColor Black -BackgroundColor Orange
    New-ConditionalText -Range "I:I" -ConditionalType ContainsText -Text ".Request" -ConditionalTextColor DarkGreen -BackgroundColor $null
    New-ConditionalText -Range "I:I" -ConditionalType ContainsText -Text ".Resp." -ConditionalTextColor Orange -BackgroundColor $null
    New-ConditionalText -Range "I:I" -ConditionalType ContainsText -Text "IPM.OLE.CLASS" -ConditionalTextColor Plum -BackgroundColor $null

    #FreeBusyStatus
    New-ConditionalText -Range "O3:O9999" -ConditionalType ContainsText -Text "Free" -ConditionalTextColor Red -BackgroundColor $null
    New-ConditionalText -Range "O3:O9999" -ConditionalType ContainsText -Text "Tentative" -ConditionalTextColor Orange -BackgroundColor $null
    New-ConditionalText -Range "O3:O9999" -ConditionalType ContainsText -Text "Busy" -ConditionalTextColor Green -BackgroundColor $null

    #Shared Calendar information
    New-ConditionalText -Range "T3:T9999" -ConditionalType NotEqual -Text "Not Shared" -ConditionalTextColor Blue -BackgroundColor $null
    New-ConditionalText -Range "U:U" -ConditionalType ContainsText -Text "TRUE" -ConditionalTextColor Blue -BackgroundColor $null
    New-ConditionalText -Range "V3:V9999" -ConditionalType NotEqual -Text "NotFound" -ConditionalTextColor Blue -BackgroundColor $null

    #AppointmentAuxiliaryFlags
    New-ConditionalText -Range "AH3:AH9999" -ConditionalType ContainsText -Text "Copy" -ConditionalTextColor DarkRed -BackgroundColor LightPink
)

function FormatHeader {
    param(
        [object] $excel
    )
    $sheet = $excel.Workbook.Worksheets[$ShortId]
    $HeaderRow = 2
    $n = 0

    # Static List of Columns for now...
    $sheet.Column(++$n) | Set-ExcelRange -Width 6 -HorizontalAlignment center         # LogRow
    Set-CellComment -Text "This is the Enhanced Calendar Logs for [$Identity] for MeetingID `n [$($script:GCDO[0].CleanGlobalObjectId)]." -Row $HeaderRow -ColumnNumber $n -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -NumberFormat "m/d/yyyy h:mm:ss" -HorizontalAlignment center #LastModifiedTime
    Set-CellComment -Text "LastModifiedTime: Time when the change was recorded in the CalLogs. This and all Times are in UTC." -Row $HeaderRow -ColumnNumber $n -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 11 -HorizontalAlignment center         # IsIgnorable
    Set-CellComment -Text "IsIgnorable: Can this Log be safely ignored?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # SubjectProperty
    Set-CellComment -Text "SubjectProperty: The Subject of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # Client
    Set-CellComment -Text "Client: The 'friendly' Client name of the client that made the change." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # ShortClientInfoString
    Set-CellComment -Text "ShortClientInfoString: Short Client Info String." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 5 -HorizontalAlignment Left         # ClientInfoString
    Set-CellComment -Text "ClientInfoString: Full Client Info String of client that made the change." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 12 -HorizontalAlignment Center         # TriggerAction
    Set-CellComment -Text "TriggerAction: The action that caused the change." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 25 -HorizontalAlignment Left         # ItemClass
    Set-CellComment -Text "ItemClass: The Class of the Calendar Item" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 5 -HorizontalAlignment center         # ItemVersion
    Set-CellComment -Text "ItemVersion: The Version of the Item." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 5 -HorizontalAlignment center         # AppointmentSequenceNumber
    Set-CellComment -Text "AppointmentSequenceNumber: The Sequence Number of the Appointment." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 5 -HorizontalAlignment center         # AppointmentLastSequenceNumber
    Set-CellComment -Text "AppointmentLastSequenceNumber: The Last Sequence Number of the Appointment." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # Organizer
    Set-CellComment -Text "Organizer: The Organizer of the Calendar Item." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # From
    Set-CellComment -Text "From: The SMTP address of the Organizer of the Calendar Item." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 15 -HorizontalAlignment center         # FreeBusyStatus
    Set-CellComment -Text "FreeBusyStatus: The FreeBusy Status of the Calendar Item." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # ResponsibleUser
    Set-CellComment -Text "ResponsibleUser: The Responsible User of the change." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # Sender
    Set-CellComment -Text "Sender: The Sender of the change." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 16 -HorizontalAlignment Left         # LogFolder
    Set-CellComment -Text "LogFolder: The Log Folder that the CalLog was in." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 16 -HorizontalAlignment Left         # OriginalLogFolder
    Set-CellComment -Text "OriginalLogFolder: The Original Log Folder that the item was in / delivered to." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 15 -HorizontalAlignment Right         # SharedFolderName
    Set-CellComment -Text "SharedFolderName: Was this from a Modern Sharing, and if so what Folder." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # IsFromSharedCalendar
    Set-CellComment -Text "IsFromSharedCalendar: Is this CalLog from a Modern Sharing relationship?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # ExternalSharingMasterId
    Set-CellComment -Text "ExternalSharingMasterId: If this is not [NotFound], then it is from a Modern Sharing relationship." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # ReceivedBy
    Set-CellComment -Text "ReceivedBy: The Receiver of the Calendar Item. Should always be the owner of the Mailbox." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # ReceivedRepresenting
    Set-CellComment -Text "ReceivedRepresenting: Who the item was Received for, of then the Delegate." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # MeetingRequestType
    Set-CellComment -Text "MeetingRequestType: The Meeting Request Type of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 17 -NumberFormat "m/d/yyyy h:mm:ss" -HorizontalAlignment center         # StartTime
    Set-CellComment -Text "StartTime: The Start Time of the Meeting. This and all Times are in UTC." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 17 -NumberFormat "m/d/yyyy h:mm:ss" -HorizontalAlignment center         # EndTime
    Set-CellComment -Text "EndTime: The End Time of the Meeting. This and all Times are in UTC." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # TimeZone
    Set-CellComment -Text "TimeZone: The Time Zone of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # Location
    Set-CellComment -Text "Location: The Location of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # ItemType
    Set-CellComment -Text "ItemType: The Type of the Calendar Item." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # CalendarItemType
    Set-CellComment -Text "CalendarItemType: The Calendar Item Type of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # IsException
    Set-CellComment -Text "IsException: Is this an Exception?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # RecurrencePattern
    Set-CellComment -Text "RecurrencePattern: The Recurrence Pattern of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Left         # AppointmentAuxiliaryFlags
    Set-CellComment -Text "AppointmentAuxiliaryFlags: The Appointment Auxiliary Flags of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Left         # DisplayAttendeesAll
    Set-CellComment -Text "DisplayAttendeesAll: List of the Attendees of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # AttendeeCount
    Set-CellComment -Text "AttendeeCount: The Attendee Count." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Left         # AppointmentState
    Set-CellComment -Text "AppointmentState: The Appointment State of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # ResponseType
    Set-CellComment -Text "ResponseType: The Response Type of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Right         # SentRepresentingEmailAddress
    Set-CellComment -Text "SentRepresentingEmailAddress: The Sent Representing Email Address of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Right         # SentRepresentingSMTPAddress
    Set-CellComment -Text "SentRepresentingSMTPAddress: The Sent Representing SMTP Address of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Right         # SentRepresentingDisplayName
    Set-CellComment -Text "SentRepresentingDisplayName: The Sent Representing Display Name of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Right         # ResponsibleUserSMTPAddress
    Set-CellComment -Text "ResponsibleUserSMTPAddress: The Responsible User SMTP Address of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Right         # ResponsibleUserName
    Set-CellComment -Text "ResponsibleUserName: The Responsible User Name of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment Right         # SenderEmailAddress
    Set-CellComment -Text "SenderEmailAddress: The Sender Email Address of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Left         # SenderSMTPAddress
    Set-CellComment -Text "SenderSMTPAddress: The Sender SMTP Address of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 20 -HorizontalAlignment center         # ClientIntent
    Set-CellComment -Text "ClientIntent: The Client Intent of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment Left         # NormalizedSubject
    Set-CellComment -Text "NormalizedSubject: The Normalized Subject of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # AppointmentRecurring
    Set-CellComment -Text "AppointmentRecurring: Is this a Recurring Meeting?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # HasAttachment
    Set-CellComment -Text "HasAttachment: Does this Meeting have an Attachment?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # IsCancelled
    Set-CellComment -Text "IsCancelled: Is this Meeting Cancelled?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # IsAllDayEvent
    Set-CellComment -Text "IsAllDayEvent: Is this an All Day Event?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 10 -HorizontalAlignment center         # IsSeriesCancelled
    Set-CellComment -Text "IsSeriesCancelled: Is this a Series Cancelled Meeting?" -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 17 -NumberFormat "m/d/yyyy h:mm:ss"  -HorizontalAlignment Left         # CreationTime
    Set-CellComment -Text "CreationTime: The Creation Time of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 17 -NumberFormat "m/d/yyyy h:mm:ss"  -HorizontalAlignment Left         # OriginalStartDate
    Set-CellComment -Text "OriginalStartDate: The Original Start Date of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 30 -HorizontalAlignment Left         # SendMeetingMessagesDiagnostics
    Set-CellComment -Text "SendMeetingMessagesDiagnostics: Compound Property to describe why meeting was or was not sent to everyone." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 50 -HorizontalAlignment Left         # AttendeeListDetails
    Set-CellComment -Text "AttendeeListDetails: The Attendee List Details of the Meeting, use -TrackingLogs to get values." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 50 -HorizontalAlignment Left         # AttendeeCollection
    Set-CellComment -Text "AttendeeCollection: The Attendee Collection of the Meeting, use -TrackingLogs to get values." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 40 -HorizontalAlignment Left         # CalendarLogRequestId
    Set-CellComment -Text "CalendarLogRequestId: The Calendar Log Request ID of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet
    $sheet.Column(++$n) | Set-ExcelRange -Width 120 -HorizontalAlignment Left         # CleanGlobalObjectId
    Set-CellComment -Text "CleanGlobalObjectId: The Clean Global Object ID of the Meeting." -Row $HeaderRow -ColumnNumber $n  -Worksheet $sheet

    # Update header rows after all the others have been set.
    # Title Row
    $sheet.Row(1) | Set-ExcelRange -HorizontalAlignment Left

    # Set the Header row to be bold and left aligned
    $sheet.Row($HeaderRow) | Set-ExcelRange -Bold -HorizontalAlignment Left
}