# Script to generate a table of all applications in the bucket and update README.md

param(
    [string]$BucketPath = ".\bucket",
    [string]$ReadmePath = ".\README.md"
)

function Get-AppInfoFromManifest {
    param(
        [string]$ManifestPath
    )

    try {
        $content = Get-Content $ManifestPath -Raw -Encoding UTF8
        $json = $content | ConvertFrom-Json

        $fileName = Split-Path $ManifestPath -Leaf
        $appName = $fileName -replace '.json$', ''

        return @{
            Name = $appName
            Description = $json.description
            Homepage = $json.homepage
        }
    }
    catch {
        Write-Warning "Error parsing manifest $ManifestPath : $($_.Exception.Message)"
        return $null
    }
}

# Get all JSON files in the bucket directory
$manifestFiles = Get-ChildItem -Path $BucketPath -Filter "*.json" | Sort-Object Name

Write-Host "Found $($manifestFiles.Count) manifest files"

# Extract app information from each manifest
$appInfos = @()
foreach ($file in $manifestFiles) {
    $appInfo = Get-AppInfoFromManifest -ManifestPath $file.FullName
    if ($appInfo) {
        $appInfos += $appInfo
    }
}

Write-Host "Parsed $($appInfos.Count) applications"

# Generate markdown table
$tableContent = @()
$tableContent += "| Application | Description |"
$tableContent += "| ----------- | ----------- |"

foreach ($app in $appInfos) {
    # Escape pipe characters in description to avoid breaking the table
    $escapedDescription = $app.Description -replace '\|', '\|'
    $tableContent += "| [$($app.Name)]($($app.Homepage)) | $escapedDescription |"
}

$tableString = $tableContent -join "`n"

# Read the current README content
$readmeContent = Get-Content $ReadmePath -Raw -Encoding UTF8

# Find the section to replace (between "## Applications" and next "##")
$pattern = '(?s)(## Applications.*?)(?=\n## |\Z)'
$replacement = "## Applications`n`nThis bucket currently contains the following applications:`n`n$tableString`n`n"

$updatedContent = [regex]::Replace($readmeContent, $pattern, $replacement)

# Write the updated content back to README.md
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ReadmePath, $updatedContent, $utf8NoBom)

Write-Host "Successfully updated README.md with $($appInfos.Count) applications"
