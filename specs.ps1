#Requires -Version 5.1

<#
.SYNOPSIS
    Collects basic Windows PC specifications and creates a Discord-ready report.

.DESCRIPTION
    Collects:
    - Windows version
    - Computer manufacturer and model
    - BIOS version and release date
    - CPU
    - GPU(s)
    - Installed RAM
    - Physical storage drives (SSD/HDD/NVMe when detectable)
    - Original Windows installation date
    - PowerShell version

    The formatted report is:
    - Printed in the console
    - Saved to a text file on the Desktop
    - Copied to the clipboard

.NOTES
    This script intentionally avoids collecting sensitive information such as:
    - Windows product keys
    - Serial numbers
    - IP addresses
    - MAC addresses
    - User files
#>

$ErrorActionPreference = "SilentlyContinue"

function Convert-BytesToReadableSize {
    param(
        [Parameter(Mandatory)]
        [double]$Bytes
    )

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    return "{0:N0} bytes" -f $Bytes
}

function Get-DriveType {
    param(
        [string]$MediaType,
        [string]$Model,
        [string]$BusType
    )

    $combinedInfo = "$MediaType $Model $BusType"

    if ($combinedInfo -match "NVMe") {
        return "NVMe SSD"
    }

    if ($MediaType -match "SSD" -or $Model -match "SSD|Solid State") {
        return "SSD"
    }

    if ($MediaType -match "HDD" -or $Model -match "HDD|Hard Disk") {
        return "HDD"
    }

    if ($BusType -match "USB") {
        return "External/USB"
    }

    return "Unknown"
}

Write-Host ""
Write-Host "Collecting computer specifications..." -ForegroundColor Cyan

# General system information
$computerSystem = Get-CimInstance Win32_ComputerSystem
$operatingSystem = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$videoControllers = Get-CimInstance Win32_VideoController
$physicalMemory = Get-CimInstance Win32_PhysicalMemory
$bios = Get-CimInstance Win32_BIOS | Select-Object -First 1

# Device name is optional and can be removed from the report if preferred.
$deviceName = $env:COMPUTERNAME

# CPU
$cpuName = if ($processor.Name) {
    $processor.Name.Trim()
}
else {
    "Unable to detect"
}

$cpuCores = if ($processor.NumberOfCores) {
    $processor.NumberOfCores
}
else {
    "Unknown"
}

$cpuThreads = if ($processor.NumberOfLogicalProcessors) {
    $processor.NumberOfLogicalProcessors
}
else {
    "Unknown"
}

# RAM
$totalRamBytes = ($physicalMemory | Measure-Object -Property Capacity -Sum).Sum

if (-not $totalRamBytes) {
    $totalRamBytes = $computerSystem.TotalPhysicalMemory
}

$totalRam = if ($totalRamBytes) {
    "{0:N1} GB" -f ($totalRamBytes / 1GB)
}
else {
    "Unable to detect"
}

$ramStickCount = @($physicalMemory).Count

$ramSpeedValues = $physicalMemory |
    Where-Object { $_.ConfiguredClockSpeed -or $_.Speed } |
    ForEach-Object {
        if ($_.ConfiguredClockSpeed) {
            $_.ConfiguredClockSpeed
        }
        else {
            $_.Speed
        }
    } |
    Sort-Object -Unique

$ramSpeed = if ($ramSpeedValues) {
    ($ramSpeedValues | ForEach-Object { "$_ MHz" }) -join ", "
}
else {
    "Unknown"
}

# GPU
$gpuNames = $videoControllers |
    Where-Object {
        $_.Name -and
        $_.Name -notmatch "Microsoft Basic Display Adapter|Remote Display Adapter"
    } |
    Select-Object -ExpandProperty Name -Unique

$gpuText = if ($gpuNames) {
    ($gpuNames | ForEach-Object { $_.Trim() }) -join "`n"
}
else {
    "Unable to detect"
}

# Motherboard
$baseboard = Get-CimInstance Win32_BaseBoard | Select-Object -First 1

$motherboard = if ($baseboard.Manufacturer -or $baseboard.Product) {
    "$($baseboard.Manufacturer) $($baseboard.Product)".Trim()
}
else {
    "Unable to detect"
}

# BIOS
$biosVersion = if ($bios.SMBIOSBIOSVersion) {
    $bios.SMBIOSBIOSVersion.Trim()
}
elseif ($bios.Version) {
    $bios.Version.Trim()
}
else {
    "Unable to detect"
}

$biosReleaseDate = if ($bios.ReleaseDate) {
    ([datetime]$bios.ReleaseDate).ToString("yyyy-MM-dd")
}
else {
    "Unable to detect"
}

# Storage
$storageLines = @()

# Preferred storage detection method for Windows 8/10/11.
$physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue

if ($physicalDisks) {
    foreach ($disk in $physicalDisks) {
        $driveType = Get-DriveType `
            -MediaType ([string]$disk.MediaType) `
            -Model ([string]$disk.FriendlyName) `
            -BusType ([string]$disk.BusType)

        $size = Convert-BytesToReadableSize -Bytes $disk.Size
        $model = if ($disk.FriendlyName) {
            $disk.FriendlyName.Trim()
        }
        else {
            "Unknown model"
        }

        $storageLines += "$model - $size ($driveType)"
    }
}
else {
    # Fallback for systems where Get-PhysicalDisk is unavailable.
    $diskDrives = Get-CimInstance Win32_DiskDrive

    foreach ($disk in $diskDrives) {
        $driveType = Get-DriveType `
            -MediaType ([string]$disk.MediaType) `
            -Model ([string]$disk.Model) `
            -BusType ([string]$disk.InterfaceType)

        $size = Convert-BytesToReadableSize -Bytes $disk.Size
        $model = if ($disk.Model) {
            $disk.Model.Trim()
        }
        else {
            "Unknown model"
        }

        $storageLines += "$model - $size ($driveType)"
    }
}

$storageText = if ($storageLines.Count -gt 0) {
    $storageLines -join "`n"
}
else {
    "Unable to detect"
}

# Windows information
$windowsName = $operatingSystem.Caption
$windowsBuild = $operatingSystem.BuildNumber
$windowsRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$windowsRegistry = Get-ItemProperty -Path $windowsRegistryPath -ErrorAction SilentlyContinue

$windowsRelease = if ($windowsRegistry.DisplayVersion) {
    $windowsRegistry.DisplayVersion
}
elseif ($windowsRegistry.ReleaseId) {
    $windowsRegistry.ReleaseId
}
else {
    $operatingSystem.Version
}

$fullBuildNumber = if ($null -ne $windowsRegistry.UBR) {
    "$windowsBuild.$($windowsRegistry.UBR)"
}
else {
    $windowsBuild
}

$originalInstallDate = if ($operatingSystem.InstallDate) {
    ([datetime]$operatingSystem.InstallDate).ToString("G")
}
else {
    "Unable to detect"
}

$systemModel = "$($computerSystem.Manufacturer) $($computerSystem.Model)".Trim()

if ([string]::IsNullOrWhiteSpace($systemModel)) {
    $systemModel = "Unable to detect"
}

# Discord-friendly output.
# Discord code blocks have a message-size limitation, so the report is kept concise.
$codeFence = '```'
$report = @"
**PC Specifications**

$codeFence`text
Device Name:      $deviceName
System Model:     $systemModel
Motherboard:      $motherboard
BIOS Version:     $biosVersion
BIOS Release Date: $biosReleaseDate
Operating System: $windowsName
Windows Version:  $windowsRelease (OS Build $fullBuildNumber)
Original Install Date: $originalInstallDate

CPU:
$cpuName
$cpuCores cores / $cpuThreads threads

GPU:
$gpuText

RAM:
$totalRam total
$ramStickCount installed module(s)
Speed: $ramSpeed

Storage:
$storageText

PowerShell:
$($PSVersionTable.PSVersion)
$codeFence

"@

# Save report to Desktop
$desktopPath = [Environment]::GetFolderPath("Desktop")
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$outputFile = Join-Path $desktopPath "PC-Specifications_$timestamp.txt"

$report | Set-Content -Path $outputFile -Encoding UTF8

# Copy report to clipboard
$copiedToClipboard = $false

try {
    Set-Clipboard -Value $report
    $copiedToClipboard = $true
}
catch {
    try {
        $report | clip.exe
        $copiedToClipboard = $true
    }
    catch {
        $copiedToClipboard = $false
    }
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host $report
Write-Host "==================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Report saved to:" -ForegroundColor Green
Write-Host $outputFile -ForegroundColor White

if ($copiedToClipboard) {
    Write-Host ""
    Write-Host "The report was copied to your clipboard." -ForegroundColor Green
    Write-Host "Paste it directly into the Discord ticket with Ctrl+V." -ForegroundColor Cyan
}
else {
    Write-Host ""
    Write-Host "The report could not be copied automatically." -ForegroundColor Yellow
    Write-Host "Open the saved text file and copy its contents manually." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to close"
