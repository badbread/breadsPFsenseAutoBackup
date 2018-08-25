# Enter all these values
$backupdir = "\" #where your backup files will go (leave a trailing backslash)
$appdir = "\" #where the exe lives (leave a trailing backslash)
$username = "" #PFSense Username
$pw = "" #PFSense Password
$pfaddress = "192.168.x.x" #PFSense address
$retention = "-30" #how many days to keep old backup files (Must be negative value, -30 = files older than 30 days)
$fileName = "pfsensebackup" #name of your log file (put into your $backupdir)
$usepush = "n" #use pushover? (y or n)
$pushoverapp = "c:\somepath\pushovercli.exe" #location of the pushovercli
$minbackups = "5" #minimum number of backups to keep

#Should not need to be modified
$logFileName = $fileName + ".log"
$log = $backupdir + "\" + $logFileName
$HowOld = (Get-Date).AddDays($retention);
$command= $appdir + "pfSenseBackup.exe" + " -u " + $username + " -p " + $pw + " -s " + $pfaddress + " -o " + $backupdir

function write-log {
  param(
  [parameter(Mandatory=$true)]
  [string]$text,
  [parameter(Mandatory=$true)]
  [ValidateSet("WARNING","ERROR","INFO", "AppOutput")]
  [string]$type
  )
  [string]$logMessage = [System.String]::Format("[$(Get-Date)] -"),$type, $text
  Add-Content -Path $log -Value $logMessage
}

function create_backup {
  write-log -text "Executing the backup command..." -type INFO
	$cmdOutput = Invoke-Expression $command | Out-String
  write-log -text $cmdOutput -type AppOutput
	if ($cmdOutput -like '*DONE*' )
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

function deloldbackups {
	$backupcount = ( Get-ChildItem $backupdir | Measure-Object ).Count
	if ($backupcount -gt $minbackups) {
			write-log -text "Attempting to delete old backups..." -type INFO;
			get-childitem -Path $backupdir -recurse | where-object { !$_.PSIsContainer -and $_.lastwritetime -lt $HowOld } | remove-item -force
			write-log -text "Backups older than $HowOld days deleted." -type INFO;
			alldone;
		          }
	else {
		write-log -text "There are not at least $minbackups backup files, not deleting anything..." -type WARNING;
		alldone;
		}
}

function alldone {
	write-log -text "Backup completed successfully" -type INFO;
	write-host "Backup complete."
	exit
}

function sendpush($message) {
  if ($usepush = "y") {
  write-log -text "Push notification sent" -type INFO;
  $message = $message.ForEach({ "PFSense BACKUP - " + $message})
  & $pushoverapp message="$message";
  exit
}
  else {
  write-log -text "Push not used or variable incorrect"
  exit
  }
}

Add-Content -Path $log -Value "--------------------------------------------------------------------"
Add-Content -Path $log -Value "Backup process started"

create_backup;
