#Requires -Version 5.1
<#
.SYNOPSIS
    Checks for a new P4V installer build and updates the Chocolatey package files.

.DESCRIPTION
    This script is designed to run in a GitHub Actions workflow on a windows-latest runner.
    It discovers the latest Perforce P4V release, compares the SHA256 hash of p4vinst64.exe
    against the hash currently in chocolateyinstall.ps1, and if a change is detected, it
    silently installs the new binary, extracts the full version via 'p4v.exe -V', and updates
    p4v.nuspec and tools/chocolateyinstall.ps1.

.NOTES
    Exit codes:
      0 - Success (no update needed, or update applied successfully)
      1 - Error during execution
#>

[CmdletBinding()]
param(
    # Root of the repository checkout
    [string]$RepoRoot = $PWD
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Configuration ──────────────────────────────────────────────────────────────
$releasesIndexUrl  = 'https://filehost.perforce.com/perforce/'
$perforceBaseUrl   = 'https://filehost.perforce.com/perforce'
$installerFileName = 'p4vinst64.exe'

$installScriptPath = Join-Path $RepoRoot 'tools\chocolateyinstall.ps1'
$nuspecPath        = Join-Path $RepoRoot 'p4v.nuspec'

# ── Helper Functions ───────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
        default { Write-Host "[$timestamp] $Message" }
    }
}

function Get-LatestReleaseDirectory {
    <#
    .SYNOPSIS
        Scrapes the Perforce CDN index for release directories and returns them
        sorted newest-first. Then probes each to find the latest one that actually
        hosts p4vinst64.exe.
    #>
    Write-Log "Scraping $releasesIndexUrl for release directories..."
    try {
        $response = Invoke-WebRequest -Uri $releasesIndexUrl -UseBasicParsing
    }
    catch {
        Write-Log "Failed to fetch releases index: $_" -Level ERROR
        return $null
    }

    # Extract all rYY.N patterns from the page
    $versionStrings = [regex]::Matches($response.Content, 'r(\d{2}\.\d+)/') |
        ForEach-Object { $_.Groups[1].Value } |
        Sort-Object -Unique

    if (-not $versionStrings) {
        Write-Log "No release directories found on the index page." -Level ERROR
        return $null
    }

    Write-Log "Found release directories: $($versionStrings -join ', ')"

    # Sort descending by version number and probe for the installer
    $sorted = $versionStrings |
        ForEach-Object { [PSCustomObject]@{ Tag = "r$_"; Version = [System.Version]$_ } } |
        Sort-Object -Property Version -Descending

    foreach ($release in $sorted) {
        $probeUrl = "$perforceBaseUrl/$($release.Tag)/bin.ntx64/$installerFileName"
        Write-Log "Probing $probeUrl ..."
        try {
            Invoke-WebRequest -Uri $probeUrl -Method Head -UseBasicParsing -ErrorAction Stop | Out-Null
            Write-Log "Found active release: $($release.Tag)"
            return $release.Tag
        }
        catch {
            Write-Log "  -> Not available (HTTP error). Trying next." -Level WARN
        }
    }

    Write-Log "No release directory contains $installerFileName." -Level ERROR
    return $null
}

function Get-RemoteChecksum {
    param([string]$ReleaseTag)
    <#
    .SYNOPSIS
        Downloads the SHA256SUMS file for a release and extracts the hash for p4vinst64.exe.
    #>
    $sumsUrl = "$perforceBaseUrl/$ReleaseTag/bin.ntx64/SHA256SUMS"
    Write-Log "Fetching checksums from $sumsUrl ..."
    try {
        $response = Invoke-WebRequest -Uri $sumsUrl -UseBasicParsing
        $content  = [System.Text.Encoding]::UTF8.GetString($response.Content)
    }
    catch {
        Write-Log "Failed to download SHA256SUMS: $_" -Level ERROR
        return $null
    }

    Write-Log "SHA256SUMS content (first 500 chars):`n$($content.Substring(0, [Math]::Min(500, $content.Length)))"

    # Format is:  <hash> *<filename>   or   <hash>  <filename>
    $match = $content | Select-String -Pattern "([a-fA-F0-9]{64})\s+\*?$installerFileName"
    if ($match) {
        $hash = $match.Matches[0].Groups[1].Value.ToLower()
        Write-Log "Remote hash for ${installerFileName}: $hash"
        return $hash
    }

    Write-Log "Could not find hash for $installerFileName in SHA256SUMS." -Level ERROR
    return $null
}

function Get-CurrentChecksum {
    <#
    .SYNOPSIS
        Parses the current $checksum64 value from chocolateyinstall.ps1.
    #>
    Write-Log "Reading current checksum from $installScriptPath ..."
    $content = Get-Content $installScriptPath -Raw
    $match   = $content | Select-String -Pattern "\`$checksum64\s*=\s*'([a-fA-F0-9]{64})'"
    if ($match) {
        $hash = $match.Matches[0].Groups[1].Value.ToLower()
        Write-Log "Current hash in repo: $hash"
        return $hash
    }
    Write-Log "Could not parse checksum64 from $installScriptPath." -Level ERROR
    return $null
}

function Install-P4VSilently {
    param([string]$InstallerPath)
    <#
    .SYNOPSIS
        Silently installs P4V using the downloaded installer.
    #>
    Write-Log "Installing P4V silently from $InstallerPath ..."
    $proc = Start-Process -FilePath $InstallerPath `
                          -ArgumentList '/s /v"/qn"' `
                          -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Log "Installer exited with code $($proc.ExitCode)." -Level ERROR
        return $false
    }
    Write-Log "P4V installation completed successfully."
    return $true
}

function Get-P4VVersion {
    <#
    .SYNOPSIS
        Runs 'p4v.exe -V' to extract the full version string and converts it to
        a Chocolatey-compatible version (e.g. 2025.4.2871449).
    .NOTES
        p4v.exe -V outputs something like:
          Rev. P4V/NTX64/2025.4/2871449 (2025/05/20).
        We want to extract "2025.4.2871449".
    #>
    # Search common install locations
    $searchPaths = @(
        "${env:ProgramFiles}\Perforce\p4v.exe",
        "${env:ProgramFiles(x86)}\Perforce\p4v.exe"
    )

    $p4vExe = $null
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $p4vExe = $path
            break
        }
    }

    if (-not $p4vExe) {
        # Fallback: search Program Files recursively
        Write-Log "p4v.exe not found in standard locations, searching Program Files..."
        $found = Get-ChildItem -Path $env:ProgramFiles -Filter 'p4v.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $p4vExe = $found.FullName
        }
    }

    if (-not $p4vExe) {
        Write-Log "Could not locate p4v.exe after installation." -Level ERROR
        return $null
    }

    Write-Log "Found p4v.exe at: $p4vExe"
    Write-Log "Running: & `"$p4vExe`" -V"

    # p4v.exe -V prints version info then exits; capture all output
    try {
        $output = & $p4vExe -V 2>&1 | Out-String
    }
    catch {
        Write-Log "Failed to run p4v.exe -V: $_" -Level ERROR
        return $null
    }

    Write-Log "p4v.exe -V output:`n$output"

    # Parse: "Rev. P4V/NTX64/2025.4/2871449"  →  "2025.4.2871449"
    $match = $output | Select-String -Pattern 'P4V/\w+/(\d{4}\.\d+)/(\d+)'
    if ($match) {
        $majorMinor = $match.Matches[0].Groups[1].Value   # e.g. 2025.4
        $changelist = $match.Matches[0].Groups[2].Value    # e.g. 2871449
        $version    = "$majorMinor.$changelist"             # e.g. 2025.4.2871449
        Write-Log "Extracted version: $version"
        return $version
    }

    Write-Log "Could not parse version from p4v.exe -V output." -Level ERROR
    return $null
}

function Update-PackageFiles {
    param(
        [string]$NewVersion,
        [string]$NewChecksum,
        [string]$NewReleaseTag
    )
    <#
    .SYNOPSIS
        Updates p4v.nuspec and tools/chocolateyinstall.ps1 with the new version and checksum.
    #>

    # ── Update nuspec ──
    Write-Log "Updating $nuspecPath with version $NewVersion ..."
    $nuspecContent = Get-Content $nuspecPath -Raw
    $nuspecContent = $nuspecContent -replace '<version>.*?</version>', "<version>$NewVersion</version>"
    Set-Content -Path $nuspecPath -Value $nuspecContent -NoNewline

    # ── Update chocolateyinstall.ps1 ──
    Write-Log "Updating $installScriptPath with checksum and release tag ..."
    $lines    = Get-Content $installScriptPath
    $newLines = @()

    foreach ($line in $lines) {
        if ($line -match "^\`$version\s*=\s*'.*'") {
            $newLines += "`$version = '$NewReleaseTag'"
        }
        elseif ($line -match "^\`$checksum64\s*=\s*'[a-fA-F0-9]+'") {
            $newLines += "`$checksum64 = '$NewChecksum'"
        }
        else {
            $newLines += $line
        }
    }

    Set-Content -Path $installScriptPath -Value $newLines

    Write-Log "Package files updated successfully."
}

# ── Main ───────────────────────────────────────────────────────────────────────

Write-Log '════════════════════════════════════════════════════════════════'
Write-Log '  P4V Chocolatey Package Auto-Updater'
Write-Log '════════════════════════════════════════════════════════════════'

# 1. Discover latest release
$latestRelease = Get-LatestReleaseDirectory
if (-not $latestRelease) {
    Write-Log "Aborting: could not determine latest release." -Level ERROR
    exit 1
}

# 2. Fetch remote hash
$remoteHash = Get-RemoteChecksum -ReleaseTag $latestRelease
if (-not $remoteHash) {
    Write-Log "Aborting: could not fetch remote checksum." -Level ERROR
    exit 1
}

# 3. Compare with current hash
$currentHash = Get-CurrentChecksum
if (-not $currentHash) {
    Write-Log "Aborting: could not read current checksum from repo." -Level ERROR
    exit 1
}

if ($remoteHash -eq $currentHash) {
    Write-Log "Hashes match — package is up to date. Nothing to do."
    # Signal to GitHub Actions that no update was made
    if ($env:GITHUB_OUTPUT) {
        "updated=false" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    }
    exit 0
}

Write-Log "Hash change detected!"
Write-Log "  Current : $currentHash"
Write-Log "  Remote  : $remoteHash"

# 4. Download the installer
$tempDir       = Join-Path $env:TEMP "p4v-update-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$installerPath = Join-Path $tempDir $installerFileName
$downloadUrl   = "$perforceBaseUrl/$latestRelease/bin.ntx64/$installerFileName"

Write-Log "Downloading $downloadUrl ..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
Write-Log "Download complete: $installerPath ($(((Get-Item $installerPath).Length / 1MB).ToString('F1')) MB)"

# Verify downloaded file hash
$downloadedHash = (Get-FileHash -Path $installerPath -Algorithm SHA256).Hash.ToLower()
Write-Log "Downloaded file hash: $downloadedHash"
if ($downloadedHash -ne $remoteHash) {
    Write-Log "HASH MISMATCH! Downloaded file hash does not match SHA256SUMS." -Level ERROR
    Write-Log "  Expected : $remoteHash"
    Write-Log "  Got      : $downloadedHash"
    exit 1
}
Write-Log "Hash verification passed."

# 5. Install silently and extract version
$installOk = Install-P4VSilently -InstallerPath $installerPath
if (-not $installOk) {
    Write-Log "Aborting: P4V installation failed." -Level ERROR
    exit 1
}

$newVersion = Get-P4VVersion
if (-not $newVersion) {
    Write-Log "Aborting: could not extract version from p4v.exe." -Level ERROR
    exit 1
}

# 6. Update package files
Update-PackageFiles -NewVersion $newVersion -NewChecksum $remoteHash -NewReleaseTag $latestRelease

Write-Log "Update complete: version $newVersion, hash $remoteHash"

# 7. Signal to GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "updated=true"         | Out-File -FilePath $env:GITHUB_OUTPUT -Append
    "version=$newVersion"  | Out-File -FilePath $env:GITHUB_OUTPUT -Append
}

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Log '════════════════════════════════════════════════════════════════'
Write-Log "  Done — package updated to $newVersion"
Write-Log '════════════════════════════════════════════════════════════════'
