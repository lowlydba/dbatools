function Select-DbaBackupInformation{
<#
    .SYNOPSIS 
    Select a subset of backups from a dbatools backup history object

    .DESCRIPTION
    Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

    .PARAMETER BackupHistory
    A dbatools.BackupHistory object containing backup history records

    .PARAMETER RestoreTime
        The point in time you want to restore to

    .PARAMETER IgnoreLogs
        This switch will cause Log Backups to be ignored. So will restore to the last Full or Diff backup only
    .PARAMETER IgnoreDiffs
        This switch will cause Differential backups to be ignored. Unless IgnoreLogs is specified, restore to point in time will still occur, just using all available log backups
    .PARAMETER DatabaseName
        A string array of Database Names that you want to filter to
    .PARAMETER ServerName
        A string array of Server Names that you want to filter    
    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
    .NOTES 
    Author:Stuart Moore (@napalmgram stuart-moore.com )
    DisasterRecovery, Backup, Restore
        
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
    https://dbatools.io/Set-DbaAgentJob

    .EXAMPLE   
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1)

    Returns all backups needed to restore all the backups in \\server1\backups$ to 1 hour ago

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -DatabaseName ProdFinance

    Returns all the backups needed to restore Database ProdFinance to an hour ago

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreLogs

    Returns all the backups in \\server1\backups$ to restore to as close prior to 1 hour ago as can be managed with only full and differential backups

    .EXAMPLE
    $Backups = Get-DbaBackupInformation -SqlInstance Server1 -Path \\server1\backups$
    $FilteredBackups = $Backups | Select-DbaBackupInformation -RestoreTime (Get-Date).AddHours(-1) -IgnoreDiffs

    Returns all the backups in \\server1\backups$ to restore to 1 hour ago using only Full and Diff backups.    

    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$BackupHistory,
        [DateTime]$RestoreTime = (get-date).addmonths(1),
        [switch]$IgnoreLogs,
        [switch]$IgnoreDiffs,
        [string[]]$DatabaseName,
        [string[]]$ServerName,
        [switch]$EnableException
    )
    begin{
        $InternalHistory = @()
    }
    process{
            $internalHistory += $BackupHistory
    }
    
    end{ 
        if (Test-Bound -ParameterName DatabaseName){
            $InternalHistory = $InternalHistory | Where-Object {$_.Database -in $DatabaseName}
        }
        if (Test-Bound -ParameterName ServerName){
            $InternalHistory = $InternalHistory | Where-Object {$_.InstanceName -in $servername}
        }
        
        $Databases = ($InternalHistory | Select-Object -Property Database -unique).Database
        ForEach ($Database in $Databases) {


            $DatabaseHistory = $InternalHistory | Where-Object {$_.Database -eq $Database}

            
            $dbHistory = @()
            #Find the Last Full Backup before RestoreTime
            $dbHistory += $Full =  $DatabaseHistory | Where-Object {$_.Type -in ('Full','Database') -and $_.Start -le $RestoreTime} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1

            #Find the Last diff between Full and RestoreTime
            if ($true -ne $IgnoreDiffs){
                $dbHistory += $DatabaseHistory | Where-Object {$_.Type -in ('Differential','Database Differential')  -and $_.Start -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
            }
            #Get All t-logs up to restore time
            if ($true -ne $IgnoreLogs){
                $LogBaseLsn = ($dbHistory | Sort-Object -Property LastLsn -Descending | select-object -First 1).lastLsn
                $FilteredLogs = $DatabaseHistory | Where-Object {$_.Type -in ('Log','Transaction Log') -and $_.Start -le $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN -and $_.LastLSN -ge $LogBaseLsn} | Sort-Object -Property LastLsn
                $GroupedLogs = $FilteredLogs | Group-Object -Property LastLSN, FirstLSN
                ForEach ($Group in $GroupedLogs){
                    $dbhistory += $DatabaseHistory | Where-Object {$_.BackupSetID -eq $Group.group[0].BackupSetID}
                }
            }
            # Get Last T-log
            $dbHistory += $DatabaseHistory | Where-Object {$_.Type -in ('Log','Transaction Log') -and $_.End -ge $RestoreTime -and $_.DatabaseBackupLSN -eq $Full.CheckpointLSN} | Sort-Object -Property LastLsn -Descending | Select-Object -First 1
            $dbHistory
        }    
    }
}