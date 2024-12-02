#run this script below once to generate a secure password in a string
#"Your Password Here" | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File "C:\Temp\password.txt"
$password = Get-Content "C:\Temp\password.txt" | ConvertTo-SecureString 
$credential = New-Object System.Management.Automation.PsCredential("domain\username",$password)

$Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size(512, 1024)

$logFilePath = "C:\temp\CanvasDownloads\Logs\logs.txt"  # Replace with your desired log file path


$user = ''
$pass = ''
$pair = "$($user):$($pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"
$Headers = @{Authorization = $basicAuthValue}


function Get-Timestamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
function getCreds
{


            $url="https://api-gateway.instructure.com/ids/auth/login" 
            $postParams = @{grant_type='client_credentials'}
            $results = Invoke-WebRequest -Headers $Headers -Method POST -Uri $url -Body $postParams -UseBasicParsing 
            $userobj=ConvertFrom-Json $results.content;   
            return $userobj | select access_token
}


function getTables
{

            $url="https://api-gateway.instructure.com/dap/query/canvas/table"
            $results = Invoke-WebRequest -Headers $AuthTokenHeader -Method GET -Uri $url 
            $userobj= ConvertFrom-Json $results.content;   
            return $userobj
}
function getSnapshot
{
param([Parameter()][string]$Table)
            $url="https://api-gateway.instructure.com/dap/query/canvas/table/$Table/data"
            $results = Invoke-WebRequest -Headers $AuthTokenHeader -Method POST -Uri $url -Body '{"format":"csv"}'
            $userobj=ConvertFrom-Json $results.content;   
            return $userobj
}
function getSnapshotStatus
{
param([Parameter()][string]$RequestID)

            $url="https://api-gateway.instructure.com/dap/job/$RequestID"
            $results = Invoke-WebRequest -Headers $AuthTokenHeader -Method GET -Uri $url
            $userobj=ConvertFrom-Json $results.content;   
            return $userobj
}
function getDataFile
{
param([Parameter()][string]$FileID)

            $url="https://api-gateway.instructure.com/dap/object/url"
            $results = Invoke-WebRequest -Headers $AuthTokenHeader -Method POST -Uri $url -Body $FileID
            $userobj= ConvertFrom-Json $results.content;   
            return $userobj

}
 
function downloadFile 
{
param ([string[]]$downloadlink, [string]$tableName)

$fileNumber = 1

 foreach ($download in $downloadlink)
 {

    Invoke-WebRequest $download -OutFile C:\Temp\CanvasDownloads\$tableName$fileNumber.csv.gz #-Proxy "add proxy details if needed" -ProxyCredential $credential


     $7zprogram = "C:\Program Files\7-Zip\7z.exe"
    $sourcefile = "C:\Temp\CanvasDownloads\$tableName$fileNumber.csv.gz"
    $destination = "C:\temp\CanvasDownloads"
    if(Test-Path -Path $7zprogram){
    & $7zprogram e $sourcefile "-o$destination" -y
        }else{
        Write-Host "7z.exe does not exist";
    }
    
        $outputFilePath = "C:\temp\CanvasDownloads\$tableName$fileNumber.csv"

        $fileNumber++
 }

}

function insertIntoDatabase
{
param ([string]$filePath, [string]$tableName)
# Database connection settings

write-host($filePath + " " +  $tableName)

$InsertTable = $tableName

$server = "Database Server Name"
$database = "Database Name"
$primaryKeyColumnName = "ID"
if ($tableName -eq "enrollment_states") {$primaryKeyColumnName = "enrollment_id"}

$csvFilePath = $filePath

Import-Module SqlServer

$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = "Server=$server;Database=$database;Integrated Security=True;"
$connection.Open()

# Read the CSV file
$csvData  = Import-Csv -Path $csvFilePath
$updatedCount = 0
$insertedCount = 0


foreach ($record in $csvData) {

   $newColumns = @()
    $updateRecords = @()
    $insertRecords = @()
    foreach ($value in $record.PSObject.Properties) {
        $replacePeriods = $value.name -replace '^([^\.]+\.[^\.]+)\.', '${1}_' #This removes a second period and replaces it with an underscore to deal with "value.rules.never_drop"
        $newValue = $replacePeriods -split '\.'
        #Write-Output $newValue


        # columns are by default named "value.column_name"
        # the following does that 
         if ($newValue.Count -ge 3 -and $newValue[1] -eq "turnitin_settings" -or $newValue[1] -eq "settings") { 
        $newColumns += $newValue[2]
        $curCol = $newValue[2]
            } else {
        $newColumns += $newValue[1]
        $curCol = $newValue[1] 
        }
         
        # T-SQL doesnt like reserved words like 'PUBLIC' or 'true'
        # the following also creates line by line which sets each column to insert or update a line
        # if a column is called "result" and the value is "10"", the SQL will become "SET RESULT = 10"
        
        $updateRecords+= "$($curCol -replace '(?<!_)(PUBLIC)(?!_)', '[$1]') = '$($value.Value -replace "(?<!')'(?!')", '' -replace "true", "1" -replace "false", "0")'"
        $insertRecords+= $value.Value  -replace "(?<!')'(?!')", '' -replace "true", "1" -replace "false", "0" 
        #Write-Output $newColumns

    }

    $primaryKeyValue = $insertRecords[0]
    $command = $connection.CreateCommand()
    $command.CommandText = "SELECT COUNT(*) FROM $tableName WHERE $primaryKeyColumnName = '$primaryKeyValue'"
    $recordCount = $command.ExecuteScalar()
   

    
    $columns = $newColumns -join ', '
    $inserts = $insertRecords -join "', '"
    #Write-Host $columns
    #Write-Host $inserts

        if ($recordCount -eq 0) {

            $insertCommand = $connection.CreateCommand()
            $insertCommand.CommandText = "INSERT INTO $InsertTable ($columns) VALUES ('$inserts')" -replace '(?<!_)(PUBLIC)(?!_)', '[$1]'
            #Write-Host($insertCommand.CommandText)

            try{
                $null = $insertCommand.ExecuteNonQuery()
                $insertedCount++
            }
            catch{
                 Write-Host "Failed inserting $_.Exception.Message"
                 Write-Host($insertCommand.CommandText)
            }

            if ($insertedCount % 1000 -eq 0) {
                Write-Host($insertedCount.ToString() + " " + $insertCommand.CommandText)
            }
        

        } else {

        
        $updateCommand = $connection.CreateCommand()
        $updateColumnAssignments = $updateRecords
        $updateCommand.CommandText = "UPDATE $InsertTable SET $($updateColumnAssignments -join ', ') WHERE $primaryKeyColumnName = '$primaryKeyValue'"
        #Write-Host($updateCommand.CommandText)
            try{
                $null = $updateCommand.ExecuteNonQuery()
                $updatedCount++
            }
            catch{
                 Write-Host "Failed Updating: $_.Exception.Message"
                 Write-Host($updateCommand.CommandText)
            }
            
            if ($updatedCount % 1000 -eq 0) {
                Write-Host($updatedCount.ToString() + " " + $updateCommand.CommandText)
            }

        }

    }

    Write-Host("Updated $updatedCount for $tableName")
    Write-Host("Inserted $insertedCount for $tableName")

    $logMessage = "[$(Get-Timestamp)] - Updated $updatedCount for $tableName"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage

    $logMessage = "[$(Get-Timestamp)] - Inserted $insertedCount for $tableName"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage

$connection.Close()
}


function waitForSnapshot
{
param([Parameter()][string]$requestID)

    $SnapshotStatus = 'incomplete'
    while ($SnapshotStatus -ne 'complete')
    {
        $SnapshotStatusData = getSnapshotStatus($requestID)
        $SnapshotStatus = $SnapshotStatusData.status
        if ($SnapshotStatus -ne 'complete')
        {
            Write-Output('Snapshot for ' + $table + ' is not ready yet. Waiting a minute')
            Start-Sleep -Seconds 30
            
        }
    }
    Write-Output('Snapshot is ready for ' + $table)
}



function getSnapshotDelta
{
param ([string]$Table, [string]$delatdate)

            $body = '{"format":"csv", "since":"$delatdate"}'
            $body = $body -replace '\$delatdate', $delatdate

            #$d = Get-Date $blah -Format yyyy-MM-ddTHH:mm:ssZ
            $url="https://api-gateway.instructure.com/dap/query/canvas/table/$Table/data"
            $results = Invoke-WebRequest -Headers $AuthTokenHeader -Method POST -Uri $url -Body $body
            $userobj=ConvertFrom-Json $results.content;   
            return $userobj
}

function getDeltaFromTable
{
param([Parameter()][string]$Table)

$serverName = "Database Server Name"
$databaseName = "Database Name"   
$connectionString = "Server=$serverName;Database=$databaseName;Integrated Security=True"
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString

$connection.Open()

$query = "SELECT isnull(max(ts), '1 Jan 2000') TIMESTAMP FROM $Table"  # Replace with your actual SQL query
$command = $connection.CreateCommand()
$command.CommandText = $query

$result = $command.ExecuteReader()

while ($result.Read()) {
    # Access data using $["ColumnName"]
    $returnValue =  $result["TIMESTAMP"]
}

return $returnValue

$connection.Close()

}

# this isnt every table Canvas Data 2 offers, but it's all we need
$tableList = $("account_users","accounts","assignments","assignment_groups", "course_sections", "course_sections", "enrollment_states","enrollment_terms", "learning_outcome_results","pseudonyms","quiz_submissions","quizzes","score_statistics","scores","submissions","users")

#$tableList = $("users", "enrollments", "courses", "assignments", "assignment_groups", "scores") #Only these are needed for results for PowerBI


Write-Output("Starting at [$(Get-Timestamp)]")
Get-ChildItem -Path "C:\Temp\CanvasDownloads" -File | Remove-Item -Force #Remove all previous CSV files
foreach ($table in $tableList)
{
    
    $AUTH_TOKEN = getCreds
    $AuthHeader = 'x-instauth'
    $AuthTokenHeader = @{ $AuthHeader = $AUTH_TOKEN.access_token}
    $logMessage = "[$(Get-Timestamp)] - Got the Credentials"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
  
    $date = getDeltaFromTable($table)
    $deltadate = Get-Date $date -Format "yyyy-MM-dd'T'HH:mm:ss'Z'"

    $logMessage = "[$(Get-Timestamp)] - Getting data from $table with the delta of $deltadate"
    Write-Output $logMessage  
    Add-Content -Path $logFilePath -Value $logMessage
    $tableData = getSnapshotDelta $table $deltadate
    #$tableData = getSnapshotDelta "learning_outcome_results" "2022-10-18T23:48:19Z"

    waitForSnapshot($tableData.id)
    $SnapshotStatusData = getSnapshotStatus($tableData.id)


    $FileID = ConvertTo-Json $SnapshotStatusData.objects
    $dataFile = getDataFile($FileId)
    $url = ((($dataFile.PSObject.Properties).Value).PSObject.Properties).Value
    $downloadlink = $url.url
    Write-Output('We got a download link! '+ $downloadlink)
    
    downloadFile $downloadlink $table 

    $logMessage = "[$(Get-Timestamp)] - Inserting into the database"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage


        # Specify the folder path
    $folderPath = "C:\Temp\CanvasDownloads"
    
    # Get only .csv files that begin with "blah" in the folder
    $csvFiles = Get-ChildItem -Path $folderPath -Filter "$table*.csv"
    
    # Loop through each matching .csv file and print its path
    foreach ($csvFile in $csvFiles) {

        insertIntoDatabase $csvFile.FullName $table
    }

    
    

    $logMessage = "[$(Get-Timestamp)] - Done inserting"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage


}



$logMessage = "[$(Get-Timestamp)] - We all finished whoop whoop"
    Write-Output $logMessage
    Add-Content -Path $logFilePath -Value $logMessage
