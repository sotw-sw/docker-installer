Function Test-RunAsAdministrator() {
    #Get current user context
    $CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
  
    #Check user is running the script is member of Administrator Group
    if ($CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-host "Script is running with Administrator privileges!"
    }
    else {
        #Create a new Elevated process to Start PowerShell
        $ElevatedProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
 
        # Specify the current script path and name as a parameter
        $ElevatedProcess.Arguments = "& '" + $script:MyInvocation.MyCommand.Path + "'"
 
        #Set the Process to elevated
        $ElevatedProcess.Verb = "runas"

        #Start the new elevated process
        [System.Diagnostics.Process]::Start($ElevatedProcess)
 
        #Exit from the current, unelevated, process
        Exit
 
    }
}
 
#Check Script is running with Elevated Privileges
Test-RunAsAdministrator

Write-Host "Setup for WSL2:Ubuntu..."
& wsl.exe --shutdown
& wsl.exe --install -d Ubuntu -n
& wsl.exe --set-default-version Ubuntu 2
& wsl.exe --set-default Ubuntu

$DockerPath = "$Env:ProgramFiles\Docker"

# Install
if (Test-Path -Path $DockerPath) {
    Write-Host "Docker Engine has been installed: "
    (Start-Process -FilePath "$DockerPath/docker.exe" -ArgumentList "version" -PassThru -NoNewWindow).WaitForExit()
}
else {
    Write-Host "Install Docker..."
}

# Config
$DockerConfigs = Get-ChildItem -Path $DockerPath, $(Split-Path -Parent $script:MyInvocation.MyCommand.Path) -Include "*daemon*.json" -Recurse

if ($DockerConfigs) {
    Write-Host "[0] No config"
    for ($i = 0; $i -lt $DockerConfigs.Length; $i++) {
        Write-Host "[$($i+1)] $($DockerConfigs[$i])"
    }
    
    do {
        $select = Read-Host -Prompt "Select config"
    }while (!$select -or $DockerConfigs.Length -gt $i)
    Write-Host ""

    if ($select -eq 0) {
        $DockerConfig = $null
    }
    else {
        $DockerConfig = $DockerConfigs[$select - 1]
    }
}

if ($DockerConfig) {
    if (!$DockerConfig.DirectoryName.StartsWith($DockerPath)) {
        $DockerConfigDefault = Join-Path $DockerPath -ChildPath "daemon.json"
        Copy-Item -Path $DockerConfig -Destination $DockerConfigDefault -Force
        $DockerConfig = $DockerConfigDefault
    }

    Write-Host "Docker Daemon Config: $DockerConfig"
}
else {
    Write-Host "No Docker Daemon config"
}

# Set Path
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
if ($machinePath -notlike "*;$DockerPath") {
    Write-Host "Add $DockerPath into Machine:Path"
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;$DockerPath", [System.EnvironmentVariableTarget]::Machine)
}

# Add User to group
New-LocalGroup -Name docker-users -ErrorAction SilentlyContinue
Add-LocalGroupMember -Name docker-users -Member $Env:USERNAME -ErrorAction SilentlyContinue

# Config docker service
Stop-Service -Name "docker" -Force -ErrorAction SilentlyContinue

& $DockerPath\dockerd.exe --unregister-service

if ($DockerConfig) {
    Write-Host "Register docker service with config $DockerConfig"
    & $DockerPath\dockerd.exe --register-service -G docker-users --config-file $DockerConfig
}
else {
    Write-Host "Register docker service without config"
    & $DockerPath\dockerd.exe --register-service -G docker-users 
}

Restart-Service -Name "docker" -Force

Write-Host "Docker service installed"



Write-Host ""
Read-Host -Prompt "Press any key to continue"