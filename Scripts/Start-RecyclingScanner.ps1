<#
.SYNOPSIS
    Adds new recycling assets to Recycling_Inventory.csv.

.DESCRIPTION
    Gives the operator two serial-number input options:
    1. Scan a barcode / QR code
    2. Enter the serial number manually

    Prevents duplicate inventory records and duplicate audit events.
#>

[CmdletBinding()]
param(
    [string]$CsvPath = (Join-Path $PSScriptRoot "..\data\Recycling_Inventory.csv"),
    [string]$AuditLogPath = (Join-Path $PSScriptRoot "..\logs\Scanner-Audit.csv")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AssetTypes = @(
    "Laptop","Desktop","Monitor","Printer","Hard Drive","SSD",
    "Server","Phone","Tablet","Network Device","Other"
)

$Manufacturers = @(
    "Dell","HP","Lenovo","Apple","Microsoft","Acer","ASUS","Samsung",
    "LG","ViewSonic","Epson","Canon","Brother","Lexmark","Xerox",
    "Seagate","Western Digital","Kingston","SanDisk","Toshiba",
    "Cisco","Ubiquiti","Netgear","Other"
)

$Statuses = @(
    "Received","Testing","Data Wipe Pending","Ready for Recycling",
    "Recycling","Refurbish","Parts","Completed"
)

function Select-MenuItem {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [array]$Items
    )

    while ($true) {
        Write-Host ""
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ("-" * 48)

        for ($Index = 0; $Index -lt $Items.Count; $Index++) {
            Write-Host ("[{0}] {1}" -f ($Index + 1), $Items[$Index])
        }

        $Selection = (Read-Host "SELECT").Trim()
        [int]$Number = 0

        if (
            [int]::TryParse($Selection, [ref]$Number) -and
            $Number -ge 1 -and
            $Number -le $Items.Count
        ) {
            return $Items[$Number - 1]
        }

        Write-Host "Invalid selection. Enter a menu number." -ForegroundColor Yellow
    }
}

function Select-Manufacturer {
    $Value = Select-MenuItem -Title "SELECT MANUFACTURER" -Items $Manufacturers

    if ($Value -eq "Other") {
        do {
            $Value = (Read-Host "Enter manufacturer name").Trim()
        } while ([string]::IsNullOrWhiteSpace($Value))
    }

    return $Value
}

function Get-SerialNumber {
    while ($true) {
        Write-Host ""
        Write-Host "SERIAL NUMBER INPUT" -ForegroundColor Cyan
        Write-Host ("-" * 48)
        Write-Host "[1] Scan barcode / QR code"
        Write-Host "[2] Enter serial number manually"
        Write-Host "[3] Exit scanner"

        $Choice = (Read-Host "SELECT").Trim()

        switch ($Choice) {
            "1" {
                $Value = (Read-Host "SCAN BARCODE / QR CODE").Trim()

                if (-not [string]::IsNullOrWhiteSpace($Value)) {
                    return $Value
                }

                Write-Host "No serial number was captured. Try again." -ForegroundColor Yellow
            }

            "2" {
                $Value = (Read-Host "ENTER SERIAL NUMBER").Trim()

                if (-not [string]::IsNullOrWhiteSpace($Value)) {
                    return $Value
                }

                Write-Host "Serial number cannot be blank." -ForegroundColor Yellow
            }

            "3" {
                return "EXIT"
            }

            default {
                Write-Host "Invalid selection. Enter 1, 2, or 3." -ForegroundColor Yellow
            }
        }
    }
}

function Get-NextRecordId {
    param([array]$Inventory)

    [int]$MaximumNumber = 0

    foreach ($Record in $Inventory) {
        $ExistingRecordId = [string]$Record.'Record ID'

        if ($ExistingRecordId -match '^REC-(\d+)$') {
            [int]$CurrentNumber = [int]$Matches[1]

            if ($CurrentNumber -gt $MaximumNumber) {
                $MaximumNumber = $CurrentNumber
            }
        }
    }

    [int]$NextNumber = $MaximumNumber + 1
    return "REC-" + $NextNumber.ToString("D6")
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

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " IT ASSET RECYCLING SCANNER - CSV" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Use the menu to scan or manually enter a serial number."
Write-Host ""

while ($true) {
    $SerialNumber = Get-SerialNumber

    if ($SerialNumber -eq "EXIT") {
        break
    }

    $Inventory = @(Import-Csv -Path $CsvPath)

    $Duplicate = $Inventory |
        Where-Object { $_.'Serial Number' -eq $SerialNumber } |
        Select-Object -First 1

    if ($Duplicate) {
        Write-Host ""
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host " DUPLICATE DEVICE DETECTED" -ForegroundColor Red
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host ("Serial Number: {0}" -f $Duplicate.'Serial Number')
        Write-Host ("Record ID:     {0}" -f $Duplicate.'Record ID')
        Write-Host ("Device:        {0} {1}" -f $Duplicate.Manufacturer, $Duplicate.'Asset Type')
        Write-Host ("Status:        {0}" -f $Duplicate.Status)
        Write-Host ""
        Write-Host "DEVICE NOT ADDED." -ForegroundColor Red

        Write-AuditEvent -Action "DUPLICATE_SCAN" -Record $Duplicate
        continue
    }

    $RecordId = Get-NextRecordId -Inventory $Inventory
    $AssetType = Select-MenuItem -Title "SELECT ASSET TYPE" -Items $AssetTypes
    $Manufacturer = Select-Manufacturer
    $Status = Select-MenuItem -Title "SELECT STATUS" -Items $Statuses

    $Record = [PSCustomObject][ordered]@{
        'Record ID' = $RecordId
        'Asset Type' = $AssetType
        'Manufacturer' = $Manufacturer
        'Serial Number' = $SerialNumber
        'Status' = $Status
        'Date Scanned' = (Get-Date).ToString("yyyy-MM-dd")
        'Was Asset Destroyed' = "No"
        'Date Destroyed' = ""
    }

    $Record | Export-Csv -Path $CsvPath -Append -NoTypeInformation
    Write-AuditEvent -Action "ASSET_REGISTERED" -Record $Record

    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host " ASSET REGISTERED" -ForegroundColor Green
    Write-Host "==============================================" -ForegroundColor Green
    Write-Host ("Record ID:            {0}" -f $Record.'Record ID')
    Write-Host ("Asset Type:           {0}" -f $Record.'Asset Type')
    Write-Host ("Manufacturer:         {0}" -f $Record.Manufacturer)
    Write-Host ("Serial Number:        {0}" -f $Record.'Serial Number')
    Write-Host ("Status:               {0}" -f $Record.Status)
    Write-Host ("Date Scanned:         {0}" -f $Record.'Date Scanned')
    Write-Host ("Was Asset Destroyed:  {0}" -f $Record.'Was Asset Destroyed')
    Write-Host ("Date Destroyed:       {0}" -f $Record.'Date Destroyed')
    Write-Host "=============================================="
    Write-Host ""
    Write-Host "READY FOR NEXT DEVICE..." -ForegroundColor Cyan
    Write-Host ""
}

Write-Host ""
Write-Host "Scanner closed." -ForegroundColor Cyan
