$configfilepath = $PSScriptRoot + "\autobackupconfig.xml"

# checks for an xml config file, if it doesn't exist it makes one
function Get-Config
{
	[CmdletBinding()]
	param (
		$Path
	)
	
	# If a config file exists, move on script, move on
	if (test-path -path $Path)
	{
		return (Import-Clixml $Path)
	}
	
	#if a config file does not exist, create one here
	$Config = [pscustomobject]@{
		BackupDir = Get-Folder "Select the destination for your backup files"
        null = [System.Windows.Forms.MessageBox]::Show('On the next prompt select the pfSenseBackup.exe', 'Info', 'OK', 'Information')
        AppDir    = get-filename "c:\" "Select the exe app location" -filter "pfsenseBackup.exe (*.exe) | pfSenseBackup.exe"
		Username  = get-input -WindowTitle "Enter Username" -Message "Enter your PFSense username"
		PW	      = get-input -WindowTitle "Enter Password" -Message "Enter your PFSense password" | ConvertTo-SecureString -AsPlainText -Force
		PFAddress = get-input -WindowTitle "Enter IP" -Message "Enter your PFSense IP address"
		Retention = get-input -WindowTitle "Enter Retention" -Message "How many days would you like to keep backup files before they are deleted (Enter a negative value)" -DefaultText "-30"
		Filename  = get-input -WindowTitle "Enter Logfile name" -Message "What would you like your log file name to be" -DefaultText "pfsensebackuplog.log"
		MinBackups = get-input -WindowTitle "Enter min backups" -Message "What's the minimum number of backup files to keep before auto deleting" -DefaultText "5"
		#check if push services are wanted
		UsePush   = get-input -WindowTitle "Use push services" -Message "Would you like to use a push service? (Enter y or n)" -DefaultText "y"
		PushAlways = $null
		PushOverApp = $null
		PushUser = $null
        PushKey = $null
        PushSubject = $null
	}
	#if yes to push, configure the empty variables from above
	if ($Config.usepush -eq 'y')
	{
		$Config.PushAlways = get-input -WindowTitle "Always push" -Message "Send push notification on successful backups? (Enter y or n)" -DefaultText "n"
		$null = [System.Windows.Forms.MessageBox]::Show('On the next prompt select the PS-Pushover.psm1 file', 'Info', 'OK', 'Information')
        $Config.PushOverApp = get-filename "$Config.Appdir" -filter "PS-Pushover.psm1 (*.psm1) | PS-Pushover.psm1"
		$Config.PushUser = get-input -WindowTitle "PushoverAPI User key" -Message "Enter your pushover USER KEY " -DefaultText ""
        $Config.PushKey = get-input -WindowTitle "PushoverAPI APPLICATION key" -Message "Enter your pushover APPLICATION KEY " -DefaultText ""
        $Config.PushSubject = get-input -WindowTitle "Pushover Title" -Message "Title for pushover notification" -DefaultText "PFSense Autobackup"
		$Config | Export-Clixml -Path $Path
		$Config
	}
	else
	{
		$Config | Export-Clixml $Path
		$Config
        $null = [System.Windows.Forms.MessageBox]::Show('Configuration file complete, if you need to modify any values you can edit the autobackupconfig.xml file in this scripts root directory or delete it and start over', 'Info', 'OK', 'Information')
	}
}

function Get-Filename($initialDirectory)
{
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
	$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
	$OpenFileDialog.initialDirectory = $initialDirectory
	$OpenFileDialog.ShowDialog() | Out-Null
	$OpenFileDialog.filename
	$OpenFileDialog.title
}

function Get-Folder
{
  [CmdletBinding()]
  param (
    [string]$Message,
    [string]$InitialDirectory
  )
	$browseForFolderOptions = 0
	if ($NoNewFolderButton) { $browseForFolderOptions += 512 }
	
	$app = New-Object -ComObject Shell.Application
	$folder = $app.BrowseForFolder(0, $Message, $browseForFolderOptions, $InitialDirectory)
	if ($folder)
        { 
        $selectedDirectory = $folder.Self.Path 
        }
	else 
        { 
        $selectedDirectory = '' 
        }
	[System.Runtime.Interopservices.Marshal]::ReleaseComObject($app) > $null
	return $selectedDirectory
}

function Get-Input
{
  [CmdletBinding()]
  param (
    [string]$Message,
    [string]$windowtitle,
    [string]$defaulttext
  )

	Add-Type -AssemblyName Microsoft.VisualBasic
	[Microsoft.VisualBasic.Interaction]::InputBox($Message, $WindowTitle, $DefaultText)
}


function Write-Log
{

  [CmdletBinding()]
	param (
		[parameter(Mandatory = $true)]
		[string]
		$text,
		
		[parameter(Mandatory = $true)]
		[ValidateSet("WARNING", "ERROR", "INFO", "AppOutput")]
		[string]
		$type
	)
	[string]$logMessage = [System.String]::Format("[$(Get-Date)] -"), $type, $text
	Add-Content -Path $log -Value $logMessage
}

function create_backup
{
  [CmdletBinding()]
  param (
    
  )
  
	write-log -text "Executing the backup command" -type INFO
	#decrypt the password so it can be run in the command line
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Config.pw)
    $plainpw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
	#run the .exe file with the values from the .xml file
    $command = "$($Config.appdir) -u $($Config.username) -p $($plainpw) -s $($Config.pfaddress) -o $($Config.backupdir)"
	
	$cmdOutput = Invoke-Expression $command | Out-String
	write-log -text $cmdOutput -type AppOutput
	if ($cmdOutput -like '*DONE*')
	{
		write-log -text "Copy completed successfully." -type INFO
		deloldbackups;
	}
	else
	{
		write-log -text "ERROR running copy exe" -type ERROR
		sendpush -message "PFSense auto backup failed!"
		exit
	}
}

function deloldbackups
{
	# change value entered in xml file to a valid DateTime so comparison can be done
    $HowOld = (Get-Date).AddDays($Config.retention)
	$backupcount = (Get-ChildItem $Config.backupdir -filter *.xml | Measure-Object).Count
	if ($backupcount -gt $Config.minbackups)
	{
		write-log -text "Attempting to delete old backups..." -type INFO;
		get-childitem -Path $Config.backupdir -recurse -filter *.xml | where-object { !$_.PSIsContainer -and $_.lastwritetime -lt $HowOld } | remove-item -force
		write-log -text "Backups older than $HowOld days deleted." -type INFO
		alldone;
	}
	else
	{
		write-log -text "There are not at least $($config.minbackups) backup files, not deleting anything..." -type WARNING
		alldone
	}
}

function alldone
{
	write-log -text "Backup completed successfully" -type INFO;
	write-host "Backup complete."
	if ($config.pushalways = "y")
	{
		sendpush -message "PFSense auto backup completed successfully"
		exit
	}
	else
	{
		exit
	}
}

function sendpush($message)
{
	if ($config.usepush = "y")
	{
		write-log -text "Push notification sent" -type INFO;
		$message = $message.ForEach({ "$($config.pushsubject) - " + $message })
		Send-PushoverMessage $($message) -title $($Config.pushsubject) -user $($Config.pushuser) -token $($Config.pushkey)
		exit
	}
	else
	{
		write-log -text "Push not used or variable incorrect"
		exit
	}
}

#initialize config file
$script:config = Get-Config -Path $configfilepath
# add stuff required for the pop up box
Add-Type -AssemblyName System.Windows.Forms

#setup log file
$log = $($Config.backupdir) + "\" + $($Config.fileName)
Add-Content -Path $log -Value "--------------------------------------------------------------------"
Add-Content -Path $log -Value "Backup process started"

#import the pushovercli only if using pushover
if ($config.usepush = "y")
    {
        $modulepath= $($config.AppDir -replace ("pfsensebackup.exe","")) + "PS-Pushover.psm1"
        #write-host $modulepath #DEBUGGG
        Import-Module $modulepath         
    }

#start backup process
create_backup
