# Author: Harry Moss
# Date: 02/09/2024

# Get the full path to the script
$scriptPath = $MyInvocation.MyCommand.Definition

# Get the directory where the script is located (USB drive)
$scriptDirectory = Split-Path -Parent $scriptPath

# Define the path for the log file and config file (stored on the USB)
$logFilePath = Join-Path $scriptDirectory "AutomatorLog.txt"
$configFilePath = Join-Path $scriptDirectory "AutomatorConfig.txt" # File to store version and edition information

# Function to write to the log file
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message`n"  # Adding a newline after the message
    Add-Content -Path $logFilePath -Value $logMessage
}

# Function to test network connectivity
function Test-Network {
    Write-Log "Checking for network connectivity..."
    if (-not (Test-Connection -ComputerName google.com -Count 1 -Quiet)) {
        Write-Log "No network connectivity detected. Halting execution."
        Write-Host "No network connectivity detected. Halting execution."
        throw "Network connectivity is required. Please check your connection and try again."
    } else {
        Write-Log "Network connectivity confirmed. Proceeding with setup."
        Write-Host "Network connectivity confirmed. Proceeding with setup."
    }
}

# Function to set the time zone to UTC+00:00 Dublin, Edinburgh, Lisbon, London
function Set-TimeZone {
    Write-Log "Setting time zone to (UTC+00:00) Dublin, Edinburgh, Lisbon, London..."
    try {
        tzutil /s "GMT Standard Time" # Command to set the timezone
        Write-Log "Time zone set successfully."
    } catch {
        Write-Log "Failed to set time zone. Error: $_"
    }
}

# Function to synchronise system time with an NTP server
function Sync-SystemTime {
    Write-Log "Synchronising system time..."

    try {
        # Ensure network is up before syncing
        if ((Test-Connection -ComputerName time.windows.com -Count 1 -Quiet)) {
            # Restart Windows Time service before syncing
            Restart-Service w32time
            Write-Log "Windows Time service restarted."

            # Force resync with default NTP server
            w32tm /resync
            Write-Log "System time synchronised successfully."
        } else {
            Write-Log "Time synchronisation failed. Check network adapter."
            throw "Time sync failed. Network adapter issue suspected."
        }
    } catch {
        Write-Log "System time synchronisation error: $_"
    }
}

# Read state from config file
function Get-State {
    if (Test-Path $configFilePath) {
        $config = Get-Content -Path $configFilePath
        $stateLine = $config | Select-String -Pattern "^State="
        if ($stateLine) {
            return ($stateLine -split "=")[1]
        }
    }
    return "Initial"  # Default state if no state is found
}

# Function to update the state in the config file
function Update-State {
    param (
        [string]$newState
    )
    
    if (Test-Path $configFilePath) {
        $config = Get-Content -Path $configFilePath
        $updatedConfig = @()
        
        # Check if the state line exists, and update it
        $stateUpdated = $false
        foreach ($line in $config) {
            if ($line -match "^State=") {
                $updatedConfig += "State=$newState"
                $stateUpdated = $true
            } else {
                $updatedConfig += $line
            }
        }
        
        # If state line doesn't exist, append it
        if (-not $stateUpdated) {
            $updatedConfig += "State=$newState"
        }
        
        # Save the updated config back to the file
        $updatedConfig | Set-Content -Path $configFilePath
        Write-Log "State updated to: $newState"
    } else {
        # Create config file with the new state if it doesn't exist
        "State=$newState" | Set-Content -Path $configFilePath
        Write-Log "Config file created and state set to: $newState"
    }
}

# Function to enable network adapters and handle 'Not Present' status using Get-NetAdapter
function Enable-NetworkAdapters {
    Write-Log "Attempting to restart network adapters..."
    $notPresentAdapters = Get-NetAdapter | Where-Object {$_.Status -eq 'Not Present'}
    if ($notPresentAdapters) {
        foreach ($adapter in $notPresentAdapters) {
            Write-Log "Restarting adapter: $($adapter.Name)"
            Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Adapter restarted: $($adapter.Name)"
        }
    } else {
        Write-Log "No adapters in 'Not Present' state to restart."
    }

    # After restarting, check if any adapters are disabled and enable them
    $disabledAdapters = Get-NetAdapter | Where-Object {$_.Status -eq 'Disabled'}
    if ($disabledAdapters) {
        Write-Log "Enabling network adapters..."
        $disabledAdapters | Enable-NetAdapter -Confirm:$false
        Write-Log "All network adapters successfully enabled."
    } else {
        Write-Log "All network adapters are already enabled or not present."
    }

    # Log the status of network adapters after attempting to enable
    Write-Log "Checking network adapter status after enabling..."
    Get-NetAdapter | Format-Table Name, Status, InterfaceDescription, LinkSpeed | Out-String | Add-Content -Path $logFilePath
}

# Function to disable network adapters only if they are currently enabled
function Disable-NetworkAdapters {
    $enabledAdapters = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'}
    if ($enabledAdapters) {
        Write-Log "Disabling network adapters..."
        $enabledAdapters | Disable-NetAdapter -Confirm:$false
        Write-Log "Network adapters disabled."
    } else {
        Write-Log "No network adapters were enabled. Nothing to disable."
    }

    # Log the status of network adapters after attempting to disable
    Write-Log "Checking network adapter status after disabling..."
    Get-NetAdapter | Format-Table Name, Status, InterfaceDescription, LinkSpeed | Out-String | Add-Content -Path $logFilePath
}

# Function to wait for system reboot and re-enable network adapters with 120-second delay
function WaitForRebootAndEnableNetwork {
    Write-Log "Waiting 120 seconds before proceeding with program..."

    # Implementing a 120-second delay to ensure OOBE or post-reboot state is stable
    Start-Sleep -Seconds 120

    Write-Log "Assuming OOBE screen reached."
    Enable-NetworkAdapters
}

# Function to install Windows updates (including optional/cumulative preview updates)
function Install-WindowsUpdates {

    # Install NuGet provider if not installed
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet)) {
        Write-Log "NuGet provider not found. Installing NuGet provider..."
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
            # Recheck if the NuGet provider is now available after installation
            if (Get-PackageProvider -ListAvailable -Name NuGet) {
                Write-Log "NuGet provider installed successfully."
            } else {
                Write-Log "NuGet provider installation failed. No provider found after installation."
                throw "NuGet provider installation failed."
            }
        } catch {
            Write-Log "NuGet provider installation failed. Throwing error."
            throw "NuGet provider installation failed."
        }
    } else {
        Write-Log "NuGet provider already installed."
    }

    # Install PSWindowsUpdate Module if not already installed
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "PSWindowsUpdate module not found. Attempting to install."
        try {
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber
            # Recheck if the PSWindowsUpdate module is now available after installation
            if (Get-Module -ListAvailable -Name PSWindowsUpdate) {
                Write-Log "PSWindowsUpdate module installed successfully."
            } else {
                Write-Log "PSWindowsUpdate installation failed. No module found after installation."
                throw "PSWindowsUpdate installation failed."
            }
        } catch {
            Write-Log "PSWindowsUpdate installation failed. Check network adapter. Throwing error."
            throw "PSWindowsUpdate installation failed."
        }
    } else {
        Write-Log "PSWindowsUpdate module already loaded."
    }

    # Check for all available updates, including optional/cumulative preview updates
    Write-Log "Checking for all available updates (including optional/cumulative updates)..."
    $allUpdates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose

    # Log updates found
    if ($allUpdates) {
        foreach ($update in $allUpdates) {
            $updateDetails = $update | Format-List | Out-String
            Write-Log "Update details: $updateDetails"
        }
    } else {
        Write-Log "No updates found."
    }

    # Install all available updates (including optional/cumulative updates) and log the process
    Write-Log "Installing available updates..."
    $updatesInstalled = $false

    # Install updates without auto reboot
    Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -IgnoreReboot | ForEach-Object {
        $installDetails = $_ | Format-List | Out-String
        Write-Log "Installing update details: $installDetails"
        $updatesInstalled = $true
    }

    # Check if reboot is required
    if ($updatesInstalled) {
        Write-Log "Updates installed. Forcing reboot..."
        Update-State "UpdatesContinue"

        # Attempt to initiate restart
        try {
            Write-Log "Initiating system restart..."
            Restart-Computer -Force

            # If Restart-Computer doesn't throw an error, disable adapters
            Write-Log "System restart initiated successfully."
            Disable-NetworkAdapters

            # Exit the script
            Write-Log "Exiting script as system is restarting..."
            Exit

        } catch {
            Write-Log "Failed to initiate restart. Error: $_"
            Write-Log "Network adapters will not be disabled since restart failed."
            throw "Restart failed. Please check the system and try again."
        }

    } else {
        Write-Log "No updates installed."
        Update-State "UpdatesComplete"
    }

}

# Function to check Windows version and edition
function CheckWindowsVersion {
    Write-Log "Checking Windows version and edition..."

    # Read the Windows version and edition from the config file
    if (Test-Path $configFilePath) {
        Write-Log "Reading Windows version and edition from config file..."
        $configData = Get-Content -Path $configFilePath | ConvertFrom-StringData
        $expectedWindowsVersion = $configData.WindowsVersion
        $expectedWindowsEdition = $configData.WindowsEdition
        Write-Log "Expected Windows Version: $expectedWindowsVersion, Expected Edition: $expectedWindowsEdition"
    } else {
        Write-Log "Config file not found. Please run the script first."
        throw "Config file not found."
    }

    # Get the current Windows Edition and Version
    $computerInfo = Get-ComputerInfo
    $currentWindowsEdition = $computerInfo.WindowsEditionId
    $currentWindowsVersion = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion"

    # Log the current Windows version and edition
    Write-Log "Current Windows Edition: $currentWindowsEdition"
    Write-Log "Current Windows Version: $currentWindowsVersion"

    # Validate the Windows version and edition based on user input
    if ($currentWindowsVersion -ne $expectedWindowsVersion -or $currentWindowsEdition -ne $expectedWindowsEdition) {
        Write-Log "Incorrect Windows version or edition. Expected: $expectedWindowsVersion, $expectedWindowsEdition."
        throw "Incorrect Windows version or edition detected. Please ensure the correct version is installed."
    } else {
        Write-Log "Windows version and edition verified: $expectedWindowsVersion, $expectedWindowsEdition."
    }
}

# Function to check for driver errors
function CheckDriverStatus {
    Write-Log "Checking for any device driver errors..."

    # Start the job to check for device driver errors
    $job = Start-Job -ScriptBlock {
        Get-PnpDevice -Status "Error"
    }

    # Wait for the job to complete with a 60-second timeout
    Wait-Job -Job $job -Timeout 60

    # Check if the job completed or timed out
    if ($job.State -eq "Completed") {
        # Retrieve the driver issues from the job
        $driverIssues = Receive-Job -Job $job

        if ($driverIssues) {
            Write-Log "Driver errors found:"
            $driverIssues | Format-Table -Property Class, FriendlyName, InstanceId | Out-String | Add-Content -Path $logFilePath
            Write-Log "Halting execution due to driver errors."
            throw "Driver errors detected. Please resolve the issues before proceeding."
        } else {
            Write-Log "No driver errors found."
        }
    } else {
        # If the job times out, log an error and stop the script
        Write-Log "Driver check timed out after 60 seconds."
        throw "Driver check process timed out."
    }

    # Clean up the job
    Remove-Job -Job $job

}

# Function to check for any final system errors and log details
function PerformFinalChecks {
    Write-Log "Generating error report..."

    # Get the last 10 errors from the System event log
    $errors = Get-EventLog -LogName System -EntryType Error -Newest 10

    if ($errors.Count -gt 0) {
        Write-Log "$($errors.Count) errors found in the System log."

        # Log each error in detail
        foreach ($error in $errors) {
            $errorDetails = @"

    ==================================
    Error Date:      $($error.TimeGenerated)
    Source:          $($error.Source)
    Event ID:        $($error.EventID)
    Message:         $($error.Message)
    ==================================
"@
            Write-Log $errorDetails
        }
    } else {
        Write-Log "No errors found in the System log."
    }
}

################## Main Script Execution ##################

try {
    # Step 0: Begin by testing for an active network connection & config file
    if (-not (Test-Path $configFilePath)) {
        # First, delete the old log file (if any)
        if (Test-Path $logFilePath) {
            Remove-Item $logFilePath -Force
        }

        # Begin Log and test for active connection
        Write-Log "++++++++++++++++++ LOG BEGIN ++++++++++++++++++"
        Test-Network
        
        # Prompt user for Windows version
        $windowsVersion = Read-Host "Please enter your Windows version (e.g., 23H2)"

        # Prompt user for Windows edition
        Write-Host "Please select your Windows edition:"
        Write-Host "1. Professional"
        Write-Host "2. Enterprise"
        $windowsEditionInput = Read-Host "Enter the number corresponding to your edition"
        $windowsEdition = if ($windowsEditionInput -eq '1') { 'Professional' } elseif ($windowsEditionInput -eq '2') { 'Enterprise' } else { 'Unknown' }

        # Save version and edition to config file
        Write-Log "Saving Windows version and edition to config file..."
@"
WindowsVersion=$windowsVersion
WindowsEdition=$windowsEdition
State=Initial
"@ | Set-Content -Path $configFilePath

        Write-Log "Windows version: $windowsVersion, Edition: $windowsEdition saved to $configFilePath."

        # Perform time zone setting and time synchronisation
        Set-TimeZone
        Sync-SystemTime

        # Create task with proper escaping for SCHTASKS
        $action = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\\Automator.ps1"
        $taskName = "AutomatorTask"

        # Register the scheduled task using SCHTASKS under the SYSTEM account
        $taskRunCommand = "SCHTASKS /Create /TN $taskName /TR `"$action`" /SC ONSTART /RU SYSTEM /RL HIGHEST /F"

        # Execute the command
        Invoke-Expression $taskRunCommand

        # Log that the task was successfully created
        Write-Log "Scheduled task created successfully under SYSTEM account."

        # Run the task immediately after creating it
        $taskRunNowCommand = "SCHTASKS /Run /TN $taskName"
        Invoke-Expression $taskRunNowCommand

        # Log that the task was run immediately
        Write-Log "AutomatorTask set to RUNNING state."
        Write-Log "Exiting initial setup."
        Write-Host "~~~~~~~~~~~~~~ SETUP SUCCESS ~~~~~~~~~~~~~~"
        Write-Host "Please reopen Powershell (Administrator) and run the following command for live updates:"
        Write-Host "----> Get-Content D:\AutomatorLog.txt <----"
    }
    # Log the start of the process
    Write-Log "Starting the update process..."

    # Step 1: Get current state from config
    Write-Log "Current state: $(Get-State)"

    # Step 2: Always call WaitForRebootAndEnableNetwork at start and after a reboot
    WaitForRebootAndEnableNetwork

    # Step 3: Install Windows Updates if state is Initial or UpdatesContinue
    if ((Get-State) -eq "Initial" -or (Get-State) -eq "UpdatesContinue") {
        Write-Log "Starting or resuming Windows update process..."
        Install-WindowsUpdates
    }

    # Step 4: Perform Final Checks & Clean Up task
    if ((Get-State) -eq "UpdatesComplete") {
        Write-Log "UPDATES COMPLETED: Proceeding to final checks..."
        CheckWindowsVersion
        CheckDriverStatus
        PerformFinalChecks

        # Clean up the scheduled task after all updates are complete
        Write-Log "Deleting scheduled task since updates are complete..."
        $taskDeleteCommand = "SCHTASKS /Delete /TN AutomatorTask /F"
        Invoke-Expression $taskDeleteCommand

        # Delete the config file to clean up
        if (Test-Path $configFilePath) {
            Write-Log "Deleting the config file at $configFilePath..."
            Remove-Item $configFilePath -Force
            Write-Log "Config file deleted."
        }

        Write-Log "Update process completed successfully."
        Write-Log "================== LOG END =================="
    } else {
        # Error if state is invalid or not recognised
        Write-Log "STATE ERROR: Unexpected state '$(Get-State)' in config file."
        throw "Script terminated due to unexpected state: $(Get-State)"
    }

} catch {
    Write-Log "Script terminated due to error: $_"
    Exit
}
