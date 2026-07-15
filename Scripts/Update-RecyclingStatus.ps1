<#
.SYNOPSIS
    Updates an existing recycling record and writes one unique audit event.

.DESCRIPTION
    Scanner-Audit.csv is automatically created or migrated.
    Identical audit events are not written more than once.
#>

[CmdletBinding()]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot "..\data\Recycling_Inventory.csv"),
    [string]$AuditLogPath = (Join-Path $PSScriptRoot "..\logs\Scanner-Audit.csv")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Statuses = @(
    "Received","Testing","Data Wipe Pending","Ready for Recycling",
    "Recycling","Refurbish","Parts","Completed"
)

function Test-FileLocked {
    param([string]$Path)

    $Stream = $null

    try {
        $Stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )

        return $false
    }
    catch [System.IO.IOException] {
        return $true
    }
    finally {
        if ($null -ne $Stream) {
            $Stream.Dispose()
        }
    }
}

function Wait-ForCsvAvailable {
    param([string]$Path)

    while (Test-FileLocked -Path $Path) {
        Write-Host ""
        Write-Host "CSV FILE IS CURRENTLY IN USE" -ForegroundColor Red
        Write-Host "Close Recycling_Inventory.csv in Excel or another application." -ForegroundColor Yellow
        Read-Host "After closing the CSV, press Enter to retry"
    }
}


function Initialize-AuditLog {
    $AuditDirectory = Split-Path $AuditLogPath -Parent

    if (-not (Test-Path $AuditDirectory)) {
        New-Item -ItemType Directory -Path $AuditDirectory -Force | Out-Null
    }

    if (-not (Test-Path $AuditLogPath)) {
        [PSCustomObject][ordered]@{
            'Timestamp'           = ''
            'Action'              = ''
            'Record ID'           = ''
            'Asset Type'          = ''
            'Manufacturer'        = ''
            'Serial Number'       = ''
            'Status'              = ''
            'Was Asset Destroyed' = ''
            'Date Destroyed'      = ''
            'Operator'            = ''
        } | Export-Csv -Path $AuditLogPath -NoTypeInformation

        return
    }

    $ExistingAudit = @(Import-Csv -Path $AuditLogPath)

    if ($ExistingAudit.Count -eq 0) {
        return
    }

    $FirstRecord = $ExistingAudit | Select-Object -First 1
    $PropertyNames = @($FirstRecord.PSObject.Properties.Name)

    $NeedsMigration = (
        $PropertyNames -contains 'ScannedValue' -or
        $PropertyNames -contains 'RecordID' -or
        $PropertyNames -contains 'AssetType' -or
        $PropertyNames -contains 'SerialNumber' -or
        $PropertyNames -contains 'WasAssetDestroyed' -or
        $PropertyNames -contains 'DateDestroyed'
    )

    if ($NeedsMigration) {
        $MigratedAudit = foreach ($Entry in $ExistingAudit) {
            $SerialNumber = ''

            if ($Entry.PSObject.Properties.Name -contains 'Serial Number') {
                $SerialNumber = $Entry.'Serial Number'
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'SerialNumber') {
                $SerialNumber = $Entry.SerialNumber
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'ScannedValue') {
                $SerialNumber = $Entry.ScannedValue
            }

            $RecordId = if ($Entry.PSObject.Properties.Name -contains 'Record ID') {
                $Entry.'Record ID'
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'RecordID') {
                $Entry.RecordID
            }
            else {
                ''
            }

            $AssetType = if ($Entry.PSObject.Properties.Name -contains 'Asset Type') {
                $Entry.'Asset Type'
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'AssetType') {
                $Entry.AssetType
            }
            else {
                ''
            }

            $WasDestroyed = if ($Entry.PSObject.Properties.Name -contains 'Was Asset Destroyed') {
                $Entry.'Was Asset Destroyed'
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'WasAssetDestroyed') {
                $Entry.WasAssetDestroyed
            }
            else {
                ''
            }

            $DestroyedDate = if ($Entry.PSObject.Properties.Name -contains 'Date Destroyed') {
                $Entry.'Date Destroyed'
            }
            elseif ($Entry.PSObject.Properties.Name -contains 'DateDestroyed') {
                $Entry.DateDestroyed
            }
            else {
                ''
            }

            [PSCustomObject][ordered]@{
                'Timestamp'           = $Entry.Timestamp
                'Action'              = $Entry.Action
                'Record ID'           = $RecordId
                'Asset Type'          = $AssetType
                'Manufacturer'        = $Entry.Manufacturer
                'Serial Number'       = $SerialNumber
                'Status'              = $Entry.Status
                'Was Asset Destroyed' = $WasDestroyed
                'Date Destroyed'      = $DestroyedDate
                'Operator'            = $Entry.Operator
            }
        }

        $MigratedAudit |
            Group-Object {
                '{0}|{1}|{2}|{3}|{4}|{5}' -f
                    $_.Action,
                    $_.'Record ID',
                    $_.'Serial Number',
                    $_.Status,
                    $_.'Was Asset Destroyed',
                    $_.'Date Destroyed'
            } |
            ForEach-Object {
                $_.Group | Sort-Object Timestamp | Select-Object -First 1
            } |
            Sort-Object Timestamp |
            Export-Csv -Path $AuditLogPath -NoTypeInformation
    }
}

function Write-AuditEvent {
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        $Record
    )

    Initialize-AuditLog

    $ExistingAudit = @(Import-Csv -Path $AuditLogPath)

    $ExistingEvent = $ExistingAudit |
        Where-Object {
            $_.Action -eq $Action -and
            $_.'Record ID' -eq $Record.'Record ID' -and
            $_.'Serial Number' -eq $Record.'Serial Number' -and
            $_.Status -eq $Record.Status -and
            $_.'Was Asset Destroyed' -eq $Record.'Was Asset Destroyed' -and
            $_.'Date Destroyed' -eq $Record.'Date Destroyed'
        } |
        Select-Object -First 1

    if ($ExistingEvent) {
        Write-Host ""
        Write-Host "AUDIT EVENT ALREADY EXISTS - NOT ADDED AGAIN." -ForegroundColor DarkYellow
        return
    }

    [PSCustomObject][ordered]@{
        'Timestamp'           = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        'Action'              = $Action
        'Record ID'           = $Record.'Record ID'
        'Asset Type'          = $Record.'Asset Type'
        'Manufacturer'        = $Record.Manufacturer
        'Serial Number'       = $Record.'Serial Number'
        'Status'              = $Record.Status
        'Was Asset Destroyed' = $Record.'Was Asset Destroyed'
        'Date Destroyed'      = $Record.'Date Destroyed'
        'Operator'            = $env:USERNAME
    } | Export-Csv -Path $AuditLogPath -Append -NoTypeInformation
}


if (-not (Test-Path $CsvPath)) {
    throw "Inventory CSV not found: $CsvPath"
}

Initialize-AuditLog
Wait-ForCsvAvailable -Path $CsvPath

$SearchValue = (Read-Host "Scan or enter Serial Number / Record ID").Trim()

if ([string]::IsNullOrWhiteSpace($SearchValue)) {
    throw "Serial Number or Record ID cannot be blank."
}

$Inventory = @(Import-Csv -Path $CsvPath)

$Record = $Inventory |
    Where-Object {
        $_.'Serial Number' -eq $SearchValue -or
        $_.'Record ID' -eq $SearchValue
    } |
    Select-Object -First 1

if (-not $Record) {
    Write-Host ""
    Write-Host "Record not found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " CURRENT RECYCLING RECORD" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ("Record ID:             {0}" -f $Record.'Record ID')
Write-Host ("Device:                {0} {1}" -f $Record.Manufacturer,$Record.'Asset Type')
Write-Host ("Serial Number:         {0}" -f $Record.'Serial Number')
Write-Host ("Current Status:        {0}" -f $Record.Status)
Write-Host ("Was Asset Destroyed:   {0}" -f $Record.'Was Asset Destroyed')
Write-Host ("Date Destroyed:        {0}" -f $Record.'Date Destroyed')
Write-Host "=============================================="
Write-Host ""

for ($Index = 0; $Index -lt $Statuses.Count; $Index++) {
    Write-Host ("[{0}] {1}" -f ($Index + 1),$Statuses[$Index])
}

$OldStatus = [string]$Record.Status

while ($true) {
    $Selection = (Read-Host "SELECT NEW STATUS").Trim()
    [int]$Number = 0

    if ([int]::TryParse($Selection,[ref]$Number) -and
        $Number -ge 1 -and $Number -le $Statuses.Count) {
        break
    }

    Write-Host "Invalid selection. Enter a menu number." -ForegroundColor Yellow
}

$Record.Status = $Statuses[$Number - 1]

while ($true) {
    $Destroyed = (Read-Host "Was this asset destroyed? [Y/N]").Trim()

    if ($Destroyed -match '^[Yy]$') {
        $Record.'Was Asset Destroyed' = "Yes"

        while ($true) {
            $DateText = (Read-Host "Date Destroyed [yyyy-MM-dd]").Trim()

            if ([string]::IsNullOrWhiteSpace($DateText)) {
                Write-Host "Date Destroyed is required." -ForegroundColor Yellow
                continue
            }

            [datetime]$ParsedDate = [datetime]::MinValue

            $ValidDate = [datetime]::TryParseExact(
                $DateText,
                "yyyy-MM-dd",
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref]$ParsedDate
            )

            if ($ValidDate) {
                $Record.'Date Destroyed' = $ParsedDate.ToString("yyyy-MM-dd")
                break
            }

            Write-Host "Invalid date. Use yyyy-MM-dd, for example 2026-07-10." -ForegroundColor Yellow
        }

        break
    }

    if ($Destroyed -match '^[Nn]$') {
        $Record.'Was Asset Destroyed' = "No"
        $Record.'Date Destroyed' = ""
        break
    }

    Write-Host "Enter Y or N." -ForegroundColor Yellow
}

Wait-ForCsvAvailable -Path $CsvPath
$Inventory | Export-Csv -Path $CsvPath -NoTypeInformation

Write-AuditEvent -Action "ASSET_RECORD_UPDATED" -Record $Record

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " RECORD UPDATED" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ("Record ID:             {0}" -f $Record.'Record ID')
Write-Host ("Previous Status:       {0}" -f $OldStatus)
Write-Host ("Status:                {0}" -f $Record.Status)
Write-Host ("Was Asset Destroyed:   {0}" -f $Record.'Was Asset Destroyed')
Write-Host ("Date Destroyed:        {0}" -f $Record.'Date Destroyed')
Write-Host "=============================================="
