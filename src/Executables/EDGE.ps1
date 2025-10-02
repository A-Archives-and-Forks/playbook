param (   
    [Parameter(Mandatory = $true)]
    [ValidateSet("EdgeBrowser", "WebView", "EdgeUpdate", "SetDeviceRegion", "RestoreDeviceRegion")]
    [string]$Mode,
    
    [Parameter(Mandatory = $false)]
    [int]$DeviceRegion = 244  # US (244)
)

function Set-DeviceRegion {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Region
    )
    
    Write-Host "[SetDeviceRegion] Setting device region to: $Region"
    
    try {
        $originalNation = [microsoft.win32.registry]::GetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $null)
        
        if ($null -ne $originalNation) {
            [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'OriginalNation', $originalNation, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
            Write-Host "[SetDeviceRegion] Backed up original Nation: $originalNation"
        }
        
        [microsoft.win32.registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion', 'DeviceRegion', $Region, [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null
        [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $Region, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
        
        Write-Host "[SetDeviceRegion] Device region successfully set to: $Region"
    }
    catch {
        Write-Host "[SetDeviceRegion] Failed to set device region: $_"
    }
}

function Restore-DeviceRegion {
    Write-Host "[RestoreDeviceRegion] Restoring original device region"
    
    try {
        $originalNation = [microsoft.win32.registry]::GetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'OriginalNation', $null)
        
        if ($null -ne $originalNation) {
            [microsoft.win32.registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion', 'DeviceRegion', $originalNation, [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null
            [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $originalNation, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
            
            Remove-ItemProperty -Path "HKCU:\Control Panel\International\Geo" -Name "OriginalNation" -ErrorAction SilentlyContinue | Out-Null
            
            Write-Host "[RestoreDeviceRegion] Device region and Nation restored to: $originalNation"
        } else {
            Write-Host "[RestoreDeviceRegion] No original region value was found to restore, Setting to US (244)"
            [microsoft.win32.registry]::SetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion', 'DeviceRegion', 244, [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null
            [microsoft.win32.registry]::SetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', 244, [Microsoft.Win32.RegistryValueKind]::String) | Out-Null
        }
    }
    catch {
        Write-Host "[RestoreDeviceRegion] Failed to restore device region: $_"
    }
}

function Uninstall-Process {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    try {
        $currentDeviceRegion = [microsoft.win32.registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\DeviceRegion', 'DeviceRegion', $null)
        $currentNation = [microsoft.win32.registry]::GetValue('HKEY_USERS\.DEFAULT\Control Panel\International\Geo', 'Nation', $null)
        
        if ($currentDeviceRegion -ne 244 -or $currentNation -ne "244") {
            Write-Host "[$Mode] ERROR: Device region not properly set to US (244). Current DeviceRegion: $currentDeviceRegion, Nation: $currentNation"
            Write-Host "[$Mode] This is required for Edge uninstallation. Please run SetDeviceRegion mode first with TrustedInstaller privileges."
            return
        }
        
        Write-Host "[$Mode] Device region verification passed (US=244)"
    }
    catch {
        Write-Host "[$Mode] WARNING: Could not verify device region setting: $_"
        Write-Host "[$Mode] Proceeding with uninstallation anyway..."
    }

    $baseKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    Write-Host "[$Mode] Base registry key: $baseKey"
    $registryPath = $baseKey + '\ClientState\' + $Key

    if (!(Test-Path -Path $registryPath)) {
        Write-Host "[$Mode] Registry key not found: $registryPath"
        return
    }

    Remove-ItemProperty -Path $registryPath -Name "experiment_control_labels" -ErrorAction SilentlyContinue | Out-Null
    
    try {
        # Activates BrowserReplacement and allows uninstallation directly from Settings > Apps, even after Edge gets reinstalled
        # Region must be set to non-EU country for this to work (handled separately with TrustedInstaller)
        $folderPath = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"

        if (!(Test-Path -Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }
        New-Item -ItemType File -Path $folderPath -Name "MicrosoftEdge.exe" -Force | Out-Null

    }
    catch {
        Write-Host "[$Mode] Failed to create fake MicrosoftEdge.exe: $_"
        return
    }
    

    # Setting windir temporarily to an empty string allows the Edge uninstallation to work
    # "Uninstall allowed: No Windows directory set as env var" (Legacy, not found in newer updates)
    $env:windir = ""

    $uninstallString = (Get-ItemProperty -Path $registryPath).UninstallString
    $uninstallArguments = (Get-ItemProperty -Path $registryPath).UninstallArguments

    if ([string]::IsNullOrEmpty($uninstallString) -or [string]::IsNullOrEmpty($uninstallArguments)) {
        Write-Host "[$Mode] Cannot find uninstall methods for $Mode"
        return
    }

    $uninstallArguments += " --force-uninstall --delete-profile"

    # $uninstallCommand = "`"$uninstallString`"" + $uninstallArguments
    if (!(Test-Path -Path $uninstallString)) {
        Write-Host "[$Mode] setup.exe not found at: $uninstallString"
        return
    }

    $process = Start-Process -FilePath $uninstallString -ArgumentList $uninstallArguments -Wait -Verbose -NoNewWindow -PassThru
    Write-Host "[$Mode] Uninstallation process exit code: $($process.ExitCode)"

    if ((Get-ItemProperty -Path $baseKey).IsEdgeStableUninstalled -eq 1) {
        Write-Host "[$Mode] Edge Stable has been successfully uninstalled"
    }
}

function Uninstall-Edge {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null
   
    [microsoft.win32.registry]::SetValue("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev", "AllowUninstall", 1, [Microsoft.Win32.RegistryValueKind]::DWord) | Out-Null

    Uninstall-Process -Key '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    
    @( "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$env:PUBLIC\Desktop",
        "$env:USERPROFILE\Desktop" ) | ForEach-Object {
        $shortcutPath = Join-Path -Path $_ -ChildPath "Microsoft Edge.lnk"
        if (Test-Path -Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
        }
    }

}

function Uninstall-WebView {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeWebView" -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    # Force to use system-wide WebView2 
    # [microsoft.win32.registry]::SetValue("HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge\WebView2\BrowserExecutableFolder", "*", "%%SystemRoot%%\System32\Microsoft-Edge-WebView")

    Uninstall-Process -Key '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
}

function Uninstall-EdgeUpdate {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" -Name "NoRemove" -ErrorAction SilentlyContinue | Out-Null

    $registryPath = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate'
    if (!(Test-Path -Path $registryPath)) {
        Write-Host "Registry key not found: $registryPath"
        return
    }
    $uninstallCmdLine = (Get-ItemProperty -Path $registryPath).UninstallCmdLine

    if ([string]::IsNullOrEmpty($uninstallCmdLine)) {
        Write-Host "Cannot find uninstall methods for $Mode"
        return
    }

    Write-Output "Uninstalling: $uninstallCmdLine"
    Start-Process cmd.exe "/c $uninstallCmdLine" -WindowStyle Hidden -Wait
}

switch ($Mode) {
    "EdgeBrowser" { Uninstall-Edge }
    "WebView" { Uninstall-WebView }
    "EdgeUpdate" { Uninstall-EdgeUpdate }
    "SetDeviceRegion" { Set-DeviceRegion -Region $DeviceRegion }
    "RestoreDeviceRegion" { Restore-DeviceRegion }
    default { Write-Host "Invalid mode: $Mode" }
}