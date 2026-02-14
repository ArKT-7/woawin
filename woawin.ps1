$repo = "ArKT-7/woawin"
$workdir = "$env:USERPROFILE\Downloads\woawin"
$7zUrl = "https://www.7-zip.org/a/7zr.exe"
$7zfull = "https://www.7-zip.org/a/7z2501-extra.7z"
if ($tag) {
    $target = $tag
}
elseif ($args[0]) {
    $target = $args[0]
}
if ($target) {
    $api = "https://api.github.com/repos/$repo/releases/tags/$target"
    $mode = "Release: $target"
} else {
    $api = "https://api.github.com/repos/$repo/releases/latest"
    $mode = "Release: Latest"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Clear-Host
Write-Host "`n WOAWIN Auto-Downloader & Extractor" -ForegroundColor Cyan
#Write-Host " $mode`n" -ForegroundColor Yellow

try {
    Write-Host "`n`n Fetching Release Info...`n" -ForegroundColor Yellow
    
    try {
        $release = Invoke-RestMethod -Uri $api -ErrorAction Stop
    } catch {
        if ($args[0]) {
            throw " Could not find release with tag: $tag"
        } else {
            throw " Could not find the latest release information."
        }
    }

    $assets = $release.assets | Where-Object { $_.name -match '\.zip\.\d{3}$' } | Sort-Object name
    if ($assets.Count -eq 0) {
        throw " No .zip.00x files found in this release!"
    }
    Write-Host " Parts Detected:" -ForegroundColor Gray
    
    foreach ($file in $assets) {
        $size = "{0:N2} MB" -f ($file.size / 1MB)
        $hash = $file.digest -replace 'sha256:', ''
        Write-Host " $($file.name)" -ForegroundColor Gray
        Write-Host " Size:   $size" -ForegroundColor DarkGray
        if ($hash) {
            Write-Host " SHA256: $hash" -ForegroundColor DarkGray
        } else {
            #Write-Host " SHA256: Not Provided in API..." -ForegroundColor DarkGray
        }
    }

    if (-not (Test-Path $workdir)) { 
        New-Item -Path $workdir -ItemType Directory -Force | Out-Null
    }
    Set-Location $workdir
    Write-Host " Working Directory:" -ForegroundColor Gray
    Write-Host " $workdir`n" -ForegroundColor Gray

    Write-Host "`n Setting up 7-Zip Tools...`n" -ForegroundColor Yellow
    $toolsDir = Join-Path $workdir "tools"
    if (-not (Test-Path $toolsDir)) {
        New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null 
    }
    $7zr = Join-Path $toolsDir "7zr.exe"
    $7zextra = Join-Path $toolsDir "7z-extra.7z"
    $7za = Join-Path $toolsDir "7za.exe"

    $down7z = Start-Process "curl.exe" -ArgumentList "-L", "-o", $7zr, $7zUrl, "--retry", "5" -NoNewWindow -Wait -PassThru
    if ($down7z.ExitCode -ne 0) {
        throw " Failed to download 7-Zip"
    }

    $downExtra = Start-Process "curl.exe" -ArgumentList "-L", "-o", $7zextra, $7zfull, "--retry", "5" -NoNewWindow -Wait -PassThru
    if ($downExtra.ExitCode -ne 0) {
        throw " Failed to download 7-Zip Extra"
    }

    $7zaext = Start-Process $7zr -ArgumentList "x", $7zextra, "-o$toolsDir", "-y" -NoNewWindow -Wait -PassThru
    if ($7zaext.ExitCode -ne 0) {
        throw " Failed to extract 7-Zip Tools"
    }

    Remove-Item $7zextra -Force -ErrorAction SilentlyContinue

    $folderName = $assets[0].name -replace '\.zip\.\d{3}$',''
    $subDir = Join-Path $workdir $folderName
    if (-not (Test-Path $subDir)) { 
        New-Item -Path $subDir -ItemType Directory -Force | Out-Null 
    }
    Set-Location $subDir
    
    $count = 0
    foreach ($file in $assets) {
        $count++
        $url = $file.browser_download_url
        $name = $file.name
        $expectedHash = $file.digest -replace 'sha256:', ''
        
        Write-Host "`n`n Downloading Part $count of $($assets.Count)...`n" -ForegroundColor Yellow
        $down = Start-Process "curl.exe" -ArgumentList "-L", "-o", $name, $url, "--retry", "5", "-C", "-" -NoNewWindow -Wait -PassThru
        if ($down.ExitCode -ne 0) {
            throw " Failed to dowlnoad $name"
        }

        if ($expectedHash) {
            Write-Host "`n Verifying SHA256 Cheksum... " -NoNewline -ForegroundColor DarkGray
            $Hash = (Get-FileHash $name -Algorithm SHA256).Hash
            
            if ($Hash -eq $expectedHash) {
                Write-Host "Done!" -ForegroundColor Green
            } else {
                Write-Host " Error!" -ForegroundColor Red
                Write-Host " Expected: $expectedHash" -ForegroundColor Red
                Write-Host " Got:      $Hash" -ForegroundColor Red
                Remove-Item $name -Force
                throw " Hash mismatch for $name! File deleted, Please try again..."
            }
        }
    }

    Write-Host "`n`n Verifying Archive Integrity..." -ForegroundColor Magenta
    $part1 = $assets[0].name
    $7zExe = $7za
    
    if (Test-Path $part1) {
        $test = Start-Process $7zExe -ArgumentList "t", "$part1", "-y" -NoNewWindow -Wait -PassThru
        
        if ($test.ExitCode -ne 0) {
            throw " Integrity Check Failed, Files are corupted!"
        }
        Write-Host "`n Integrity Verified!" -ForegroundColor Green

        Write-Host "`n`n Extracting ESD file..." -ForegroundColor Magenta
        $extract = Start-Process $7zExe -ArgumentList "x", "$part1", "-o$subDir", "-y" -NoNewWindow -Wait -PassThru
        if ($extract.ExitCode -ne 0) {
            throw " Extraction Failed"
        }

        $innerZip = Get-ChildItem -Path $subDir -Filter "*.zip" -Recurse | Select-Object -First 1
        if ($innerZip) {
            Write-Host "`n Nested ZIP detected, Extracting..." -ForegroundColor Cyan
            $extract2 = Start-Process $7zExe -ArgumentList "x", "$($innerZip.FullName)", "-o$subDir", "-y" -NoNewWindow -Wait -PassThru
            if ($extract2.ExitCode -ne 0) {
                throw " ESD Extraction Failed"
            }
             Remove-Item $innerZip.FullName -Force
        }
        
        $esd = Get-ChildItem -Path $subDir -Filter "*.esd" -Recurse | Select-Object -First 1
        $moved = $false

        if ($esd) {
            Write-Host "`n Found: $($esd.Name)" -ForegroundColor Green
            Move-Item $esd.FullName -Destination $workdir -Force
            if (Test-Path (Join-Path $workdir $esd.Name)) {
                $moved = $true
            }
        }

        if ($moved) {
            Write-Host "`n`n Cleaning up temporary files..." -ForegroundColor DarkGray
            Set-Location $workdir
            Remove-Item $subDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $toolsDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host " Download Complete, Opening folder...`n" -ForegroundColor Green
            Invoke-Item .
        } else {
            Write-Host "`n ERROR: .ESD file not found or move failed!" -ForegroundColor Red
            Write-Host " Check inside: $subDir" -ForegroundColor Red
        }
        Start-Sleep -Seconds 3
    } else {
        throw " Part 1 ($part1) not found!`n"
    }

} catch {
    Write-Host "`n`n Error: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host " Press Enter to exit..."
}
