$ErrorActionPreference = 'Stop'

$script:gce_install_dir = 'C:\Program Files\Google\Compute Engine'
$script:hosts_file = "$env:windir\system32\drivers\etc\hosts"

$script_drive = $PSCommandPath[0]
$builder_path = "${script_drive}:\builder\components"

function Run-Command {
 [CmdletBinding(SupportsShouldProcess=$true)]
  param (
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
      [string]$Executable,
    [Parameter(ValueFromRemainingArguments=$true,
               ValueFromPipelineByPropertyName=$true)]
      $Arguments = $null
  )
  Write-Output "Running $Executable with arguments $Arguments."
  $out = &$executable $arguments 2>&1 | Out-String
  $out.Trim()
}

function Get-MetadataValue {
  param (
    [parameter(Mandatory=$true)]
      [string]$key,
    [parameter(Mandatory=$false)]
      [string]$default
  )

  # Returns the provided metadata value for a given key.
  $url = "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$key"
  try {
    $client = New-Object Net.WebClient
    $client.Headers.Add('Metadata-Flavor', 'Google')
    return ($client.DownloadString($url)).Trim()
  }
  catch [System.Net.WebException] {
    if ($default) {
      return $default
    }
    else {
      Write-Output "Failed to retrieve value for $key."
      return $null
    }
  }
}

function Setup-NTP {
  Write-Output 'Setting up NTP.'

  # Set the CMOS clock to use UTC.
  $tzi_path = 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'
  Set-ItemProperty -Path $tzi_path -Name RealTimeIsUniversal -Value 1

  # Set up time sync...
  # Stop in case it's running; it probably won't be.
  Stop-Service W32time
  # w32tm /unregister is flaky, but using sc delete first helps to clean up
  # the service reliably.
  Run-Command $env:windir\system32\sc.exe delete W32Time

  # Unregister and re-register the service.
  $w32tm = "$env:windir\System32\w32tm.exe"
  Run-Command $w32tm /unregister
  Run-Command $w32tm /register

  # Get time from GCE NTP server every 15 minutes.
  Run-Command $w32tm /config '/manualpeerlist:metadata.google.internal,0x1' /syncfromflags:manual
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' `
    -Name SpecialPollInterval -Value 900
  # Set in Control Panel -- Append to end of list, set default.
  $server_key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers'
  $server_item = Get-Item $server_key
  $server_num = ($server_item.GetValueNames() | Measure-Object -Maximum).Maximum + 1
  Set-ItemProperty -Path $server_key -Name $server_num -Value 'metadata.google.internal'
  Set-ItemProperty -Path $server_key -Name '(Default)' -Value $server_num
  # Configure to run automatically on every start.
  Set-Service W32Time -StartupType Automatic
  Run-Command $env:windir\system32\sc.exe triggerinfo w32time start/networkon stop/networkoff
  Write-Output 'Configured W32Time to use GCE NTP server.'

  # Verify that the W32Time service is correctly installed. This has been
  # a source of flakiness in the past.
  try {
    Get-Service W32Time
  }
  catch {
    throw "Failed to configure NTP. Cannot complete image build: $($_.Exception.Message)"
  }

  # Sync time now.
  Start-Service W32time
  Run-Command $w32tm /resync
}

function Configure-Network {
  Write-Output 'Configuring network.'

  # Make sure metadata server is in etc/hosts file.
  Add-Content $script:hosts_file @'

# Google Compute Engine metadata server
    169.254.169.254    metadata.google.internal metadata

'@

  Write-Output 'Changing firewall settings.'
  # Change Windows Server firewall settings.
  # Enable ping in Windows Server 2008.
  Run-Command netsh advfirewall firewall add rule `
      name='ICMP Allow incoming V4 echo request' `
      protocol='icmpv4:8,any' dir=in action=allow

  # Enable inbound communication from the metadata server.
  Run-Command netsh advfirewall firewall add rule `
      name='Allow incoming from GCE metadata server' `
      protocol=ANY remoteip=169.254.169.254 dir=in action=allow

  # Enable outbound communication to the metadata server.
  Run-Command netsh advfirewall firewall add rule `
      name='Allow outgoing to GCE metadata server' `
      protocol=ANY remoteip=169.254.169.254 dir=out action=allow

  # Change KeepAliveTime to 5 minutes.
  $tcp_params = 'HKLM:\System\CurrentControlSet\Services\Tcpip\Parameters'
  New-ItemProperty -Path $tcp_params -Name 'KeepAliveTime' -Value 300000 -PropertyType DWord -Force

  # Disable IPv6
  Write-Output 'Disabling IPv6.'
  $ipv_path = 'HKLM:\SYSTEM\CurrentControlSet\services\TCPIP6\Parameters'
  Set-ItemProperty -Path $ipv_path -Name 'DisabledComponents' -Value 0xFF

  Write-Output 'Disabling WPAD.'

  # Mount default user registry hive at HKLM:\DefaultUser.
  Run-Command reg load 'HKLM\DefaultUser' 'C:\Users\Default\NTUSER.DAT'

  # Loop over default user and current (SYSTEM) user.
  foreach ($reg_base in 'HKLM\DefaultUser', 'HKCU') {
    # Disable Web Proxy Auto Discovery.
    $WPAD = "$reg_base\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    # Make change with reg add, because it will work with the mounted hive and
    # because it will recursively add any necessary subkeys.
    Run-Command reg add $WPAD /v AutoDetect /t REG_DWORD /d 0 /f
  }

  # Unmount default user hive.
  Run-Command reg unload 'HKLM\DefaultUser'
}

function Configure-Power {
  # Change power configuration to never turn off monitor.  If Windows turns
  # off its monitor, it will respond to power button pushes by turning it back
  # on instead of shutting down as GCE expects.  We fix this by switching the
  # "Turn off display after" setting to 0 for all power configurations.
  Get-CimInstance -Namespace 'root\cimv2\power' -ClassName Win32_PowerSettingDataIndex -ErrorAction SilentlyContinue | ForEach-Object {
    $power_setting = $_ | Get-CimAssociatedInstance -ResultClassName 'Win32_PowerSetting' -OperationTimeoutSec 10 -ErrorAction SilentlyContinue
    if ($power_setting -and $power_setting.ElementName -eq 'Turn off display after') {
      Write-Output ('Changing power setting ' + $_.InstanceID)
      $_ | Set-CimInstance -Property @{SettingIndexValue = 0}
    }
  }
}

function Change-InstanceProperties {
  Write-Output 'Setting instance properties.'

  # Enable EMS.
  Run-Command bcdedit /emssettings EMSPORT:2 EMSBAUDRATE:115200
  Run-Command bcdedit /ems on

  # Ignore boot failures.
  Run-Command bcdedit /set '{current}' bootstatuspolicy ignoreallfailures
  Write-Output 'bcdedit option set.'

  # Registry fix for PD cluster size issue.
  $vioscsi_path = 'HKLM:\SYSTEM\CurrentControlSet\Services\vioscsi\Parameters\Device'
  New-Item -Path $vioscsi_path -Force
  New-ItemProperty -Path $vioscsi_path -Name EnableQueryAccessAlignment -Value 1 -PropertyType DWord -Force

  # Change SanPolicy. Setting is persistent even after sysprep. This helps in
  # ensuring all attached disks are online when instance is built.
  $san_policy = 'san policy=OnlineAll' | diskpart | Select-String 'San Policy'
  Write-Output ($san_policy -replace '(?<=>)\s+(?=<)') # Remove newline and tabs

  # Change time zone to Coordinated Universal Time.
  Run-Command tzutil /s 'UTC'

  # Register netkvmco.dll.
  Run-Command rundll32 'netkvmco.dll,RegisterNetKVMNetShHelper'
}

function Configure-RDPSecurity {
  $registryPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'

  # Set minimum encryption level to "High"
  New-ItemProperty -Path $registryPath -Name MinEncryptionLevel -Value 3 -PropertyType DWORD -Force
  # Specifies that Network-Level user authentication is required.
  New-ItemProperty -Path $registryPath -Name UserAuthentication -Value 1 -PropertyType DWORD -Force
  # Specifies that the Transport Layer Security (TLS) protocol is used by the server and the client
  # for authentication before a remote desktop connection is established.
  New-ItemProperty -Path $registryPath -Name SecurityLayer -Value 2 -PropertyType DWORD -Force
}

function Install-Packages {
  if ($script:install_packages.ToLower() -eq 'true') {
    Write-Output 'Installing GCE packages...'
    # Install each individually in order to catch individual errors
    Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-windows
    Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-auto-updater
    Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-vss
  }
  # We always install google-compute-engine-sysprep because it is required for instance activation, it gets removed later
  Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm install google-compute-engine-sysprep
}

try {
  Write-Output 'Beginning translate powershell script.'
  $script:outs_dir = Get-MetadataValue -key 'daisy-outs-path'
  $script:install_packages = Get-MetadataValue -key 'install-gce-packages'

  Change-InstanceProperties
  Configure-Network
  Configure-Power
  Configure-RDPSecurity
  Setup-NTP
  Install-Packages

  Write-Output 'Setting up KMS activation'
  . 'C:\Program Files\Google\Compute Engine\sysprep\activate_instance.ps1'

  if ($script:install_packages.ToLower() -ne 'true') {
    Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm remove google-compute-metadata-scripts
    Run-Command 'C:\ProgramData\GooGet\googet.exe' -root 'C:\ProgramData\GooGet' -noconfirm remove google-compute-powershell
  }

  Write-Output 'Translate complete.'
}
catch {
  Write-Output 'Exception caught in script:'
  Write-Output $_.InvocationInfo.PositionMessage
  Write-Output "Message: $($_.Exception.Message)"
  Write-Output 'Translate failed'
  exit 1
}
