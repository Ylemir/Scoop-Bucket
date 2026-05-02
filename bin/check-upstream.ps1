param(
    [String[]]$Buckets = @("main", "extras"),
    [switch]$ShowMatches = $true,
    [switch]$ShowMissing = $false,
    [switch]$ShowPaths = $true,
    [int]$MaxPathsPerMatch = 5
)

if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }

$rg = Get-Command rg -ErrorAction SilentlyContinue
if (!$rg) {
    Write-Error "ripgrep (rg) not found in PATH. Please install ripgrep or ensure rg is available."
    exit 2
}

function Get-ManifestStrings($manifestPath) {
    try {
        $raw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @()
    }

    $strings = New-Object System.Collections.Generic.List[string]

    function Add-Needle([string]$s) {
        if (!$s) { return }
        $t = $s.Trim()
        if (!$t) { return }
        $strings.Add($t)
    }

    function Add-NormalizedFromUrl([string]$s) {
        if (!$s) { return }
        $t = $s.Trim()
        if (!$t) { return }

        Add-Needle $t

        try {
            $u = [Uri]$t
        } catch {
            return
        }

        $schemeHost = "{0}://{1}" -f $u.Scheme, $u.Host
        $path = $u.AbsolutePath
        if ($path -and $path -ne "/") {
            $noTrailing = $path.TrimEnd('/')
            if ($noTrailing) {
                $lastSlash = $noTrailing.LastIndexOf('/')
                if ($lastSlash -gt 0) {
                    $dirPath = $noTrailing.Substring(0, $lastSlash)
                    Add-Needle ($schemeHost + $dirPath)
                }
            }
        }

        if ($u.Host -ieq "github.com") {
            $segments = $u.AbsolutePath.Trim('/').Split('/')
            if ($segments.Length -ge 2) {
                Add-Needle ("https://github.com/{0}/{1}" -f $segments[0], $segments[1])
                Add-Needle ("github.com/{0}/{1}" -f $segments[0], $segments[1])
            }
        } else {
            $segmentsShort = $u.AbsolutePath.Trim('/').Split('/')
            if ($segmentsShort.Length -ge 1 -and $segmentsShort[0]) {
                Add-Needle ($schemeHost + "/" + $segmentsShort[0])
            }
        }
    }

    if ($json.homepage -and ($json.homepage -is [string])) {
        Add-NormalizedFromUrl $json.homepage
    }

    function Add-UrlValue($v) {
        if ($null -eq $v) { return }
        if ($v -is [string]) {
            Add-NormalizedFromUrl $v
            return
        }
        if ($v -is [System.Collections.IEnumerable]) {
            foreach ($item in $v) {
                if ($item -is [string]) {
                    Add-NormalizedFromUrl $item
                }
            }
        }
    }

    Add-UrlValue $json.url

    if ($json.architecture) {
        foreach ($p in @("64bit", "32bit")) {
            if ($json.architecture.$p) {
                Add-UrlValue $json.architecture.$p.url
            }
        }
    }

    $strings | Select-Object -Unique
}

$scoopRoot = Resolve-Path (Join-Path $env:SCOOP_HOME "..\..\..")

$localBucketDir = Resolve-Path (Join-Path $PSScriptRoot "..\bucket")

$appFiles = Get-ChildItem -Path $localBucketDir -Filter "*.json" -File | Sort-Object Name
$apps = $appFiles | ForEach-Object { $_.BaseName }

$officialBucketDirs = @()
foreach ($b in $Buckets) {
    $p = Join-Path $scoopRoot "buckets\$b\bucket"
    if (Test-Path $p) {
        $officialBucketDirs += (Resolve-Path $p)
    }
}

if ($officialBucketDirs.Count -eq 0) {
    Write-Error "No official bucket directories found under '$scoopRoot'. Tried: $($Buckets -join ', ')"
    exit 2
}

$nameMatches = New-Object System.Collections.Generic.List[string]
$contentMatches = New-Object System.Collections.Generic.List[string]
$missing = New-Object System.Collections.Generic.List[string]

$nameMatchPaths = @{}
$contentMatchPaths = @{}

foreach ($file in $appFiles) {
    $app = $file.BaseName
    $foundByName = $false
    $foundByContent = $false
    $pathsByName = @()
    $pathsByContent = @()

    foreach ($dir in $officialBucketDirs) {
        $candidate = Join-Path $dir ("{0}.json" -f $app)
        if (Test-Path -LiteralPath $candidate) {
            $foundByName = $true
            $pathsByName += $candidate
            break
        }
    }

    if (!$foundByName) {
        $needles = Get-ManifestStrings -manifestPath $file.FullName
        if ($needles.Count -gt 0) {
            foreach ($dir in $officialBucketDirs) {
                $rgArgs = @('-l', '--fixed-strings')
                foreach ($needle in $needles) {
                    $rgArgs += @('-e', $needle)
                }
                $rgArgs += @($dir)

                $hitFiles = & $rg.Source @rgArgs 2>$null
                if ($LASTEXITCODE -eq 0 -and $hitFiles) {
                    $foundByContent = $true
                    $pathsByContent += $hitFiles
                    break
                }
            }
        }
    }

    if ($foundByName) {
        $nameMatches.Add($app)
        if ($pathsByName.Count -gt 0) {
            $nameMatchPaths[$app] = ($pathsByName | Select-Object -Unique | Select-Object -First $MaxPathsPerMatch)
        }
    } elseif ($foundByContent) {
        $contentMatches.Add($app)
        if ($pathsByContent.Count -gt 0) {
            $contentMatchPaths[$app] = ($pathsByContent | Select-Object -Unique | Select-Object -First $MaxPathsPerMatch)
        }
    } else {
        $missing.Add($app)
    }
}

Write-Host "Checked $($apps.Count) manifests in '$localBucketDir'" -ForegroundColor DarkGray
Write-Host "Found in official bucket(s) by name: $($nameMatches.Count)" -ForegroundColor Green
Write-Host "Found in official bucket(s) by content: $($contentMatches.Count)" -ForegroundColor Green
Write-Host "Not found in official bucket(s): $($missing.Count)"

if ($ShowMatches -and (($nameMatches.Count + $contentMatches.Count) -gt 0)) {
    if ($nameMatches.Count -gt 0) {
        Write-Host "Matches (name):" -ForegroundColor Cyan
        $nameMatches | ForEach-Object {
            Write-Host "- $_" -ForegroundColor Yellow
            if ($ShowPaths -and $nameMatchPaths.ContainsKey($_)) {
                $nameMatchPaths[$_] | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
            }
        }
    }
    if ($contentMatches.Count -gt 0) {
        Write-Host "Matches (content):" -ForegroundColor Cyan
        $contentMatches | ForEach-Object {
            Write-Host "- $_" -ForegroundColor Yellow
            if ($ShowPaths -and $contentMatchPaths.ContainsKey($_)) {
                $contentMatchPaths[$_] | ForEach-Object { Write-Host "  - $_" -ForegroundColor DarkGray }
            }
        }
    }
}

if ($ShowMissing -and $missing.Count -gt 0) {
    Write-Host "Missing:" -ForegroundColor Blue
    $missing | ForEach-Object { Write-Host "- $_" }
}

if (($nameMatches.Count + $contentMatches.Count) -gt 0) { exit 1 }
exit 0
