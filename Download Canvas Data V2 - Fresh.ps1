#run this script below once to generate a secure password in a string
#"Your Password Here" | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString | Out-File "C:\Temp\password.txt"

$user = ''
$pass = ''
$pair = "$($user):$($pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"
$Headers = @{Authorization = $basicAuthValue}

$password = Get-Content "C:\Temp\password.txt" | ConvertTo-SecureString 
$credential = New-Object System.Management.Automation.PsCredential("DOMAIN\USER",$password)

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
param([Parameter()][string[]]$downloadlink)
$fileNumber = 1

 foreach ($download in $downloadlink)
 {
    Invoke-WebRequest $download -Proxy "http://proxy.education.tas.gov.au:8080" -ProxyCredential $credential -OutFile C:\Temp\CanvasDownloads\$table$fileNumber.csv.gz


     $7zprogram = "C:\Program Files\7-Zip\7z.exe"
    $sourcefile = "C:\Temp\CanvasDownloads\$table$fileNumber.csv.gz"
    $destination = "C:\temp\CanvasDownloads"
    if(Test-Path -Path $7zprogram){
    & $7zprogram e $sourcefile "-o$destination"
        }else{
        Write-Host "7z.exe does not exist";
    }

        $fileNumber++
 }
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
            Start-Sleep -Seconds 15
            
        }
    }
    Write-Output('Snapshot is ready for ' + $table)
}



#Authentication times out after too many requests so split the tables up

$tableList = getTables
#$tableList.tables

#$tableList = $("accounts", "account_users", "assignments", "courses", "course_sections","enrollments")
#$tableList =  @("enrollment_states","enrollment_terms", "quizzes","quiz_submissions","scores","submissions","score_statistics","users","pseudonyms")


Write-Output("Starting at $(get-date -Format "HH:mm")")
foreach ($table in $tableList.tables -gt "e")
{
    
    $AUTH_TOKEN = getCreds
    $AuthHeader = 'x-instauth'
    $AuthTokenHeader = @{ $AuthHeader = $AUTH_TOKEN.access_token}
    Write-Output('Got the street cred yo')
   
    $tableData = getSnapshot($table)
    Write-Output('Requested the Snapshot for ' + $table)
    waitForSnapshot($tableData.id)
    $SnapshotStatusData = getSnapshotStatus($tableData.id)


    $FileID = ConvertTo-Json $SnapshotStatusData.objects
    $dataFile = getDataFile($FileId)
    $url = ((($dataFile.PSObject.Properties).Value).PSObject.Properties).Value
    $downloadlink = $url.url
    Write-Output('We got a download link! '+ $downloadlink)
    
    downloadFile($downloadlink) 
    Write-Output('Downloaded and extracted to folder!')

}


Write-Output("Finished at $(get-date -Format "HH:mm")")

$tableList.tables -gt "e"