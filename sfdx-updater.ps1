
<# 
	For the given context directory, check if any child directory is an sfdx project. 
	If yes, commit any uncommitted changes, pull code from the org, and commit.
	Log file at ./sfdx-updater.log
 #>
param (
	[Parameter(Mandatory=$false, Position=0)]
	[Alias("p")]
	[string]$contextPath,

	[Parameter(Mandatory=$false, Position=1)]
	[Alias("l")]
	[string]$logPath
)
$originPath = Get-Location
if (-not(Test-Path $contextPath)) {
	$contextPath = $originPath
}
if (-not(Test-Path $logPath)) {
	$logPath = $originPath
}
$configPath = ".sfdx/sfdx-config.json"
$logFile = $logPath + "/sfdx-updater.log"
$dirsUpdated = @()
$dirsWithNoChanges = @()
$dirsWithInvalidCreds = @()
$dirsWithErrors = @()
$directories = Get-ChildItem -Directory -Path $contextPath 
# $directories = Get-ChildItem -Directory -Path $contextPath -Recurse -Depth 2

function Write-Log {
    param([string]$message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Value "$time - $message" -Path $logFile
}

$hr = "---------------"
Write-Log "$hr Org Updater START $hr"
Write-Log "$hr Initial State"
Write-Log "Context path: $contextPath"
Write-Log "Log file: $logFile"
Write-Log "$hr Processing directories"

# Loop child directories
foreach($directory in $directories) {
    $path = $directory.FullName
		Write-Log "Processing $path"
    cd $path

		#Check if there's an sfdx config file
    if (-not(Test-Path $configPath)) {
			Write-Log "No config found at $path"
			continue
		}
			
		#Check for uncommitted changes
		$uncommittedChanges = git status -s
		if ($uncommittedChanges) {
			try {
				git add .
				git commit -m "Org Updater: Uncommitted changes found"
				Write-Log "Committed changes in directory $path"
			} catch {
				Write-Log "Error committing changes in directory $path"
				continue
			}
		} 

		#Get org username
		$username = (Get-Content $configPath | ConvertFrom-Json).defaultusername
		if ($username -eq $null) {
			Write-Log "Username not found for directory $path"
			continue
		}

		#Validate credentials
		$orgInfo = sfdx org display --json | ConvertFrom-Json
		if ($orgInfo.result.connectedStatus -ne "Connected") {
			Write-Log "Invalid credentials found for org $username in directory $path"
			$dirsWithInvalidCreds += $path
			continue
		}
		
		#Pull code & commit
		try {
			Write-Log "Starting retrieve from org $username"
			sfdx project retrieve start -o $username -x "manifest/package.xml"
			Write-Log "Finished retrieve from org $username"
			
			$newChangesFound = git status -s
			if(-not($newChangesFound)) {
				Write-Log "No new changes found. Continuing..."
				$dirsWithNoChanges += $path
				continue
			}
			
			git add .
			git commit -m "Org Updater: Auto-update from org $username"
			Write-Log "Successfully retrieved and committed changes from org $username"
			$dirsUpdated += $path
		} catch {
			Write-Log "Error retrieving and committing changes from org $username in directory $path"
			$dirsWithErrors += $path
			continue
		}
}

Write-Log "$hr Final State"
Write-Log "Projects updated: $dirsUpdated"
Write-Log "Projects with no changes: $dirsWithNoChanges"
Write-Log "Directories with invalid creds: $dirsWithInvalidCreds"
Write-Log "Directories with errors: $dirsWithErrors"

Write-Log "$hr Org Updater END $hr"
cd $originPath