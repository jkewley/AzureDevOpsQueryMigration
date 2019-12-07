<####################################################################################
Name: CopyWorkItemQueries.ps1

Version: 1.0

Author: Josh Kewley

Company: Blue Chip Consulting Group

Description:
  This script will copy the hierarchy of work item queries from one Azure DevOps instance to another
  Useful if you are migrating from one organization to another, or if you have a templated AZDO process that you would like to replicate to another tenant

  To begin, you will need to provide values for the placeholder globals defined below

  Queries REST API documentation: https://docs.microsoft.com/en-us/rest/api/azure/devops/wit/queries?view=azure-devops-rest-5.1

History:
1.0 intial file creation and documentation
####################################################################################>

$global:projectName = "ConotoWeb"           # The name of the AZDO project. This script assumes you are copying between two projects with the same name
$global:sourceOrganization = "contoso"      # The moniker of the organization which contains the queres to be copied
$global:destOrganization = "adventureworks" # The moniker of the organization where the queries will be copied
$global:sourceToken = "asdfghjklzxcvbnmqwertyiop1234567890987654321abcdefgh"  # PAT with permmission to read the source queries
$global:destToken = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"    # PAT with permission to create new queries


$sourceUrl = "https://dev.azure.com/$($sourceOrganization)"
$destUrl = "https://dev.azure.com/$($destOrganization)"

# Checks for the presence of the named query in the project at the destination organization
function TestForPresenceAtTarget {
    param(
        [string]$query,
        [hashtable]$destheader
    )
   try{$results = Invoke-RestMethod -Uri $query -Headers $destheader}
   catch{}
   return ($null -ne $results) 
}

# replaces source organization url references in queries with the destination organization url
function CleanProjectReferences {
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { CleanProjectReferences $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = CleanProjectReferences $property.Value
            }

            $hash
        }
        else
        {
            if ($InputObject -is [string]) {
                $InputObject.Replace($sourceOrganization, $destOrganization)
            }
            else {$InputObject}
        }
    }
}

# Creates the query in the project at the destination
function CreateQueryInTarget {
    param(
        [psobject]$queryObject,
        [string]$createUrl, 
        [hashtable]$header
    )
    #remove properties which will be assigned at destination
    $queryObject.PSObject.properties.remove('id')
    $queryObject.PSObject.properties.remove('_links')
    $queryObject.PSObject.properties.remove('url')
    #update internal references with the target environemnt
    $replaced = CleanProjectReferences -InputObject $queryObject
    #gotta go deep with this because of the nesting allowed with query clause grouping
    $bodyHashTable = ConvertTo-Json $replaced -Depth 10


    # The actual POST can fail in some cases, especially if the migration is from an older version of AZDO to a newer one and internal identifier strategies don't align
    # for example: Process work item custom fields used to have the internal name [processName].[FieldName] but now they care called Custom.[FieldName]
    #              if those fields are used in an output column of a query it could fail
    # note that AZDO returns the actual error in the http response which PS doesn't provide access to. Fix forthcoming: https://github.com/PowerShell/PowerShell/issues/5555
    # in the meantime use fiddler to see the error in the failed payload
    $results=$null
    try{
        $results = Invoke-RestMethod -Method 'Post' -ContentType "application/json" -Uri $createUrl -Headers $header -Body $bodyHashTable -ErrorVariable httpError# (forthcoming in future version of PS) -SkipHttpErrorCheck
        return $results
    }
    catch{
        Write-Host "     $($httpError)"
        Write-Host "Error processing $($createUrl) : $($results.message)"
        Write-Host "     $($_.Exception)"
    } 
}

# Runs through queries and folders in the source, copying them to the destination 
function ProcessQueryFolder() {
    param(
        [psobject]$children
    )
    $children | ForEach-Object {
        #process queries in current folder
        $targetUri = "$($destUrl)/$($projectName)/_apis/wit/queries/$($_.path)?api-version=5.1"
        #queries and folders need to be posted to the parent
        $parentFolderUri = "$($targetUri.Substring(0, $targetUri.LastIndexOf('/')))?api-version=5.1"
        #only used for tracing
        $parentPath = $_.path.Substring(0, $_.path.LastIndexOf('/'))

        if ($_.isFolder -ne $true) {
            #test for presence of query in target
            if(TestForPresenceAtTarget -query $targetUri -destheader $destheader){
                #skip if found
                Write-Host " [SKIP QUERY] '$($_.name)' found at : $($_.path)" -ForegroundColor Gray
            } else {
                #otherwise create the query in its parent folder
                Write-Host "Creating query '$($_.name)' under '$($parentPath)'" -ForegroundColor Yellow
                $queryInTarget = CreateQueryInTarget -queryObject $_ -createUrl $parentFolderUri -header $destheader
                Write-Host "'$($queryInTarget.name)' was added under '$($parentPath)'" -ForegroundColor Green
            }
        } else {
            #test for presence of folder in target
            if(TestForPresenceAtTarget -query $targetUri -destheader $destheader){
                #skip if found
                Write-Host " [SKIP FOLDER] '$($_.name)' found at : $($_.path)"  -ForegroundColor Gray
            } else {
                #otherwise create the folder under its parent folder
                Write-Host "Creating folder '$($_.name)' under '$($parentPath)'" -ForegroundColor Yellow
                try{
                    $body = @{
                                name="$($_.name)" 
                                isFolder=$true
                              } | ConvertTo-Json
                    $folderResponse = Invoke-RestMethod -Method 'Post' -ContentType "application/json" -Uri $parentFolderUri -Headers $destheader -Body $body
                    Write-Host "'$($folderResponse.name)' was added under '$($parentPath)'" -ForegroundColor Green
                }
                catch{
                    Write-Host "Error creating folder $($_.name) : $($_.Exception)" -ForegroundColor Red
                }
            }
            #recursively call the method to create children folders and queries of the new folder
            ProcessQueryFolder -children $_.Children
        }
    }
}

Write-Host "Initialize authentication headers" -ForegroundColor Yellow
$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($sourceToken)"))
$sourceheader = @{authorization = "Basic $token"}

$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($destToken)"))
$destheader = @{authorization = "Basic $token"}

#This is the source query hierarchy which will be migrated
$sourceQueriesUrl = "$($sourceUrl)/$($projectName)/_apis/wit/queries?`$depth=2&`$expand=all&api-version=5.1"
$sourceFolders = Invoke-RestMethod -Uri $sourceQueriesUrl -Method Get -ContentType "application/json" -Headers $sourceheader

#useful to test queries against the destination ad-hoc.
#Invoke-RestMethod -Uri "$($sourceUrl)/$($projectName)/_apis/wit/queries/Shared%20Queries/Dashboard/Bugs%20by%20Environment%20Found?api-version=5.1" -Method Get -ContentType "application/json" -Headers $destheader
#break

$sourceFolders.value | ForEach-Object {
    # white list Shared Queries 
    if ($_.name -eq "Shared Queries") {
        ProcessQueryFolder -children $_.Children
    }
}