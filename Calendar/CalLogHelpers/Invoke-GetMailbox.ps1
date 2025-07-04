﻿# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

$WellKnownCN_CA = "MICROSOFT SYSTEM ATTENDANT"
$CalAttendant = "Calendar Assistant"
$WellKnownCN_Trans = "MicrosoftExchange"
$Transport = "Transport Service"
<#
.SYNOPSIS
Get the Mailbox for the Passed in Identity.
Might want to extend to do 'Get-MailUser' as well.
.PARAMETER CN of the Mailbox
    The mailbox for which to retrieve properties.
.PARAMETER Organization
    [Optional] Organization to search for the mailbox in.
#>
function GetMailbox {
    param(
        [string]$Identity,
        [string]$Organization,
        [bool]$UseGetMailbox
    )

    if ($Identity -like "*<*") {
        $Identity = $Identity -split "<" | Select-Object -Last 1
        $Identity = $Identity -split ">" | Select-Object -First 1
        Write-Verbose "Refined Identity to [$Identity]"
    }

    $params = @{Identity = $Identity
        ErrorAction      = "SilentlyContinue"
    }

    if ($UseGetMailbox) {
        $Cmdlet = "Get-Mailbox"
        $params.Add("IncludeInactiveMailbox", $true)
    } else {
        $Cmdlet = "Get-Recipient"
    }

    try {
        Write-Verbose "Searching $Cmdlet $(if (-not ([string]::IsNullOrEmpty($Organization))) {"with Org: $Organization"}) for $Identity."

        if (-not ([string]::IsNullOrEmpty($Organization)) -and $script:MSSupport) {
            Write-Verbose "Using Organization parameter"
            $params.Add("Organization", $Organization)
        } elseif (-not ([string]::IsNullOrEmpty($Organization))) {
            Write-Verbose "Using -OrganizationalUnit parameter with $Organization."
            $params.Add("Organization", $Organization)
        }

        Write-Verbose "Running $Cmdlet with params: $($params.Values)"
        $RecipientOutput = & $Cmdlet @params
        Write-Verbose "RecipientOutput: $RecipientOutput"

        if (!$RecipientOutput) {
            Write-Host "Unable to find [$Identity]$(if ($Organization -ne `"`" ) {" in Organization:[$Organization]"})."
            Write-Host "Trying to find a Group Mailbox for [$Identity]..."
            $RecipientOutput = Get-Mailbox -Identity $Identity -ErrorAction SilentlyContinue -GroupMailbox
            if (!$RecipientOutput) {
                Write-Host "Unable to find a Group Mailbox for [$Identity] either."
                return $null
            } else {
                Write-Verbose "Found GroupMailbox [$($RecipientOutput.DisplayName)]"
            }
        }

        if ($null -eq $script:PIIAccess) {
            [bool]$script:PIIAccess = CheckForPIIAccess($RecipientOutput.DisplayName)
        }

        if ($script:PIIAccess) {
            Write-Verbose "Found [$($RecipientOutput.DisplayName)]"
        } else {
            Write-Verbose "No PII Access for [$Identity]"
        }

        return $RecipientOutput
    } catch {
        Write-Error "An error occurred while running ${Cmdlet}: [$_]"
    }
}

<#
.SYNOPSIS
Checks the identities are EXO Mailboxes.
#>
function CheckIdentities {
    if (Get-Command -Name Get-Mailbox -ErrorAction SilentlyContinue) {
        Write-Host "Validated connection to Exchange Online..."
    } else {
        Write-Error "Get-Mailbox cmdlet not found. Please validate that you are running this script from an Exchange Management Shell and try again."
        Write-Host "Look at Import-Module ExchangeOnlineManagement and Connect-ExchangeOnline."
        exit
    }

    # See if it is a Customer Tenant running the cmdlet. (They will not have access to Organization parameter)
    $script:MSSupport = [Bool](Get-Help Get-Mailbox -Parameter Organization -ErrorAction SilentlyContinue)
    Write-Verbose "MSSupport: $script:MSSupport"

    Write-Host "Checking for at least one valid mailbox..."
    $IdentityList = @()

    Write-Host "Preparing to check $($Identity.count) Mailbox(es)..."

    foreach ($Id in $Identity) {
        [bool]$script:CalLogsDisabled = $false
        $Account = GetMailbox -Identity $Id -UseGetMailbox $true
        if ($null -eq $Account) {
            # -or $script:MB.GetType().FullName -ne "Microsoft.Exchange.Data.Directory.Management.Mailbox") {
            Write-DashLineBoxColor "`n Error: Mailbox [$Id] not found on Exchange Online.  Please validate the mailbox name and try again.`n" -Color Red
            continue
        }
        if (-not (CheckForPIIAccess($Account.DisplayName))) {
            Write-Host -ForegroundColor DarkRed "No PII access for Mailbox [$Id]. Falling back to SMTP Address."
            $IdentityList += $ID
            if ($null -eq $script:MB) {
                $script:MB = $Account
            }
        } else {
            Write-Host "Mailbox [$Id] found as : $($Account.DisplayName)"
            $IdentityList += $Account.PrimarySmtpAddress.ToString()
            if ($null -eq $script:MB) {
                $script:MB = $Account
            }
        }
        # Need to reset between users!!!
        if ($Account.CalendarVersionStoreDisabled -eq $true) {
            $script:CalLogsDisabled = $true
            Write-Host -ForegroundColor DarkRed "Mailbox [$Id] has CalendarVersionStoreDisabled set to True.  This mailbox will not have Calendar Logs."
            Write-Host -ForegroundColor DarkRed "Some logs will be available for Mailbox [$Id] but they will not be complete."
        }
        if ($Account.RecipientTypeDetails -eq "RoomMailbox" -or $Account.RecipientTypeDetails -eq "EquipmentMailbox") {
            if ($script:PIIAccess -eq $true) {
                $script:Rooms += $Account.PrimarySmtpAddress.ToString()
            } else {
                $script:Rooms += $Id
            }
            Write-Host -ForegroundColor Green "[$Id] is a Room / Equipment Mailbox."
        }
    }

    Write-Verbose "IdentityList: $IdentityList"

    if ($IdentityList.count -eq 0) {
        Write-DashLineBoxColor "`n No valid mailboxes found.  Please validate the mailbox name and try again. `n" Red
        exit
    }

    return $IdentityList
}

<#
.SYNOPSIS
Creates a list of CN that are used in the Calendar Logs, Looks up the Mailboxes and stores them in the MailboxList.
#>
function ConvertCNtoSMTP {
    # Creates a list of CN's that we will do MB look up on
    $CNEntries = @()
    $CNEntries += ($script:GCDO.ResponsibleUserName.ToUpper() | Select-Object -Unique)
    $CNEntries += ($script:GCDO.SentRepresentingEmailAddress.ToUpper() | Select-Object -Unique)
    $CNEntries += ($script:GCDO.Sender.ToUpper() | Select-Object -Unique)
    # $CNEntries += ($script:GCDO.SenderEmailAddress.ToUpper() | Select-Object -Unique)
    $CNEntries = $CNEntries | Select-Object -Unique
    Write-Verbose "`t Have $($CNEntries.count) CN Entries to look for..."
    Write-Verbose "CNEntries: "; foreach ($CN in $CNEntries) { Write-Verbose `t`t$CN }

    $Org = $script:MB.OrganizationalUnit.split('/')[-1]

    # Creates a Dictionary of MB's that we will use to look up the CN's
    Write-Verbose "Converting CN entries into SMTP Addresses..."

    foreach ($CNEntry in $CNEntries) {
        Write-Verbose  "Processing CNEntry: [$CNEntry]"
        if ($CNEntry -like $WellKnownCN_CA) {
            $script:MailboxList[$CNEntry] = $CalAttendant
        } elseif ($CNEntry -like $WellKnownCN_Trans) {
            $script:MailboxList[$CNEntry] = $Transport
        } elseif ($CNEntry -match 'cn=([\w,\s.@-]*[^/])$') {
            Write-Verbose  "Using Get MB to look up [$CNEntry]"
            $script:MailboxList[$CNEntry] = (GetMailbox -Identity $CNEntry -Organization $Org)
        } elseif ($CNEntry -like "*<*@*>") {
            Write-Verbose "Passing in SMTP address [$CNEntry] to GetSMTPAddress"
            $script:MailboxList[$CNEntry] = GetSMTPAddress -PassedCN $Cn
        } elseif ($CNEntry -like '*</O=*>') {
            $Cn = $CNEntry -split "<" | Select-Object -Last 1
            $Cn = $Cn -split ">" | Select-Object -First 1
            Write-Verbose  "`t Working on [$CN]"
            $script:MailboxList[$CNEntry] = GetMailboxProp -PassedCN $Cn -Prop "PrimarySmtpAddress"
        } else {
            Write-Verbose "ConvertCNtoSMTP: Passed in Value does not look like a CN or SMTP Address: [$CNEntry]"
        }

        $script:MailboxList[$CNEntry] = $CNEntry
    }
    Write-Verbose "MailboxList: $($script:MailboxList.Count) entries found."

    foreach ($key in $script:MailboxList.Keys) {
        $value = $script:MailboxList[$key]
        Write-Verbose "$key :: $($value.DisplayName)"
    }
}

<#
.SYNOPSIS
Gets DisplayName from a passed in CN that matches an entry in the MailboxList
#>
function GetDisplayName {
    param(
        $PassedCN
    )
    Write-Verbose "GetDisplayName:: Working on [$PassedCN]"
    if ($PassedCN.Properties.Name -contains 'DisplayName') {
        return GetMailboxProp -PassedCN $PassedCN -Prop "DisplayName"
    } elseif ($PassedCN -match '<' ) {
        return $PassedCN.ToString().split("<")[0].replace('"', '')
    } elseif ($PassedCN -match '\[OneOff') {
        return $PassedCN.ToString().split('"')[1]
    } else {
        Write-Verbose "Unable to get the DisplayName for [$PassedCN]"
        return $PassedCN
    }
}

<#
.SYNOPSIS
Gets SMTP Address from a passed in CN that matches an entry in the MailboxList
#>
function GetSMTPAddress {
    param(
        $PassedCN
    )

    #Write-Verbose "GetSMTPAddress:: Working on [$PassedCN]"
    if ($PassedCN -match $WellKnownCN_Trans) {
        return $Transport
    } elseif ($PassedCN -match $WellKnownCN_CA) {
        return $CalAttendant
    } elseif ($PassedCN -like "*<*@*>") {
        # This is a new format that we are seeing in the Calendar Logs.
        # Example: '"Jon Doe" <Jon.Doe@Contoso.com>'
        $SMTPAddress = $($PassedCN -split ("<")[-1] -split (">")[0])[1].Trim()
        Write-Verbose "GetSMTPAddress: Using <SMTPAddress> format of [$PassedCN] as [$SMTPAddress]"
        return $SMTPAddress
    } elseif ($PassedCN -match '</O=') {
        #Matching "Users Name" </O=...>
        $pattern = "<([^>]*)>"
        #$matches = [regex]::Matches($PassedCN, $pattern)
        $MailboxOU = ([regex]::Matches($PassedCN, $pattern)).groups[1].value
        Write-Verbose "GetSMTPAddress: Using /OU format to look up mailbox for [$MailboxOU]"
        return GetMailboxProp -PassedCN $MailboxOU -Prop "PrimarySmtpAddress"
    } elseif ($PassedCN -match 'cn=([\w,\s.@-]*[^/])$') {
        Write-Verbose "GetSMTPAddress: Using CN format to look up mailbox for [$PassedCN]"
        return GetMailboxProp -PassedCN $PassedCN -Prop "PrimarySmtpAddress"
    } elseif (($PassedCN -match "NotFound") -or ([string]::IsNullOrEmpty($PassedCN))) {
        return ""
    } elseif ($PassedCN -match "InvalidSchemaPropertyName") {
        Write-Verbose "GetSMTPAddress: Passed in Value is empty or not Valid: [$PassedCN]."
        return ""
    } elseif ($PassedCN -match "@") {
        Write-Verbose "GetSMTPAddress: Looks like we have an SMTP Address already: [$PassedCN]."
        $PassedCN.SMTPAddress
        return $PassedCN
    } else {
        # We have a problem, we don't have a CN or an SMTP Address
        Write-Warning "GetSMTPAddress: Passed in Value does not look like a CN or SMTP Address: [$PassedCN]."
        return $PassedCN
    }
}

<#
.SYNOPSIS
    This function gets a more readable Name from a CN or the Calendar Assistant.
.PARAMETER PassedCN
    The common name (CN) of the mailbox user or the Calendar Assistant.
.OUTPUTS
    Returns the last part of the CN so that it is more readable
#>
function BetterThanNothingCNConversion {
    param (
        $PassedCN
    )
    if ($PassedCN -match $WellKnownCN_CA) {
        return $CalAttendant
    }

    if ($PassedCN -match $WellKnownCN_Trans) {
        return $Transport
    }

    if ($PassedCN -match 'cn=([\w,\s.@-]*[^/])$') {
        $cNameMatch = $PassedCN -split "cn="

        # Normally a readable name is sectioned off with a "-" at the end.
        # Example /o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=d61149258ba04404adda42f336b504ed-Delegate
        if ($cNameMatch[-1] -match "-[\w* -.]*") {
            Write-Verbose "BetterThanNothingCNConversion: Matched : [$($cNameMatch[-1])]"
            $cNameSplit = $cNameMatch.split('-')[-1]
            # Sometimes we have a more than one "-" in the name, so we end up with only 1-4 chars which is too little.
            # Example: .../CN=RECIPIENTS/CN=83DAA772E6A94DA19402AA6B41770486-4DB5F0EB-4A
            if ($cNameSplit.length -lt 5) {
                Write-Verbose "BetterThanNothingCNConversion: [$cNameSplit] is too short"
                $cNameSplit= $cNameMatch.split('-')[-2] + '-' + $cNameMatch.split('-')[-1]
                Write-Verbose "BetterThanNothingCNConversion: Returning Lengthened : [$cNameSplit]"
            }
            Write-Verbose "BetterThanNothingCNConversion: Returning : [$cNameSplit]."
            return $cNameSplit
        }
        # Sometimes we do not have the "-" in front of the Name.
        # Example: "/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=user123"
        if ($cNameMatch[-1] -match "[\w* -.]*") {
            Write-Verbose "BetterThanNothingCNConversion: Returning : [$($cNameMatch[-1])]"
            return $cNameMatch.split('-')[-1]
        }
    }
}

<#
.SYNOPSIS
Checks if an entries is Redacted to protect PII.
#>
function CheckForPIIAccess {
    param(
        $PassedString
    )
    if ($PassedString -match "REDACTED-") {
        return $false
    } else {
        return $true
    }
}

<#
.SYNOPSIS
    Retrieves mailbox properties for a given mailbox.
.DESCRIPTION
    This function retrieves mailbox properties for a given mailbox using Exchange Web Services (EWS).
.PARAMETER CN of the Mailbox
    The mailbox for which to retrieve properties.
.PARAMETER PropertySet
    The set of properties to retrieve.
#>
function GetMailboxProp {
    param(
        $PassedCN,
        $Prop
    )

    Write-Debug "GetMailboxProp: [$Prop]: Searching for:[$PassedCN]..."

    if (($Prop -ne "PrimarySmtpAddress") -and ($Prop -ne "DisplayName")) {
        Write-Error "GetMailboxProp:Invalid Property: [$Prop]"
        return "Invalid Property"
    }

    if ($script:MailboxList.count -gt 0) {
        switch -Regex ($PassedCN) {
            $WellKnownCN_CA {
                return $CalAttendant
            }
            $WellKnownCN_Trans {
                return $Transport
            }
            default {
                if ($null -ne $script:MailboxList[$PassedCN]) {
                    $ReturnValue = $script:MailboxList[$PassedCN].$Prop

                    if ($null -eq $ReturnValue) {
                        Write-Error "`t GetMailboxProp:$Prop :NotFound for ::[$PassedCN]"
                        return BetterThanNothingCNConversion($PassedCN)
                    }

                    Write-Verbose "`t GetMailboxProp:[$Prop] :Found::[$ReturnValue]"
                    if (-not (CheckForPIIAccess($ReturnValue))) {
                        Write-Verbose "No PII Access for [$ReturnValue]"
                        return BetterThanNothingCNConversion($PassedCN)
                    }
                    return $ReturnValue
                } else {
                    Write-Verbose "`t GetMailboxProp:$Prop :NotFound::$PassedCN"
                    return BetterThanNothingCNConversion($PassedCN)
                }
            }
        }
    } else {
        Write-Host -ForegroundColor Red "$script:MailboxList is empty, unable to do CN to SMTP mapping."
        return BetterThanNothingCNConversion($PassedCN)
    }
}
