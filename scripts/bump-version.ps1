#!/usr/bin/env pwsh
param(
    [switch]$Minor,
    [switch]$Major,
    [switch]$Test
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = "$scriptDir/../"

# Find all csproj files with AssemblyVersion
$projects = Get-ChildItem -Path $srcDir -Filter "*.csproj" -Recurse
$maxVersion = [Version]"0.0.0"

foreach ($project in $projects) {
    $xml = [Xml](Get-Content $project.FullName)
    $assemblyVersion = ($xml.Project.PropertyGroup | Where-Object { $_.AssemblyVersion }).AssemblyVersion
    if ($assemblyVersion) {
        $version = [Version]$assemblyVersion
        if ($version -gt $maxVersion) {
            $maxVersion = $version
        }
    }
}

# Find all package.json files with, not under node_modules
$packageJsonFiles = Get-ChildItem -Path $srcDir -Filter "package.json" -Recurse | Where-Object { $_.FullName -notmatch "node_modules" }
$frontendVersions = @{}

foreach ($pkg in $packageJsonFiles) {
    $json = Get-Content $pkg.FullName -Raw | ConvertFrom-Json
    if ($json.version) {
        $version = [Version]$json.version
        $frontendVersions[$pkg.FullName] = $version
        if ($version -gt $maxVersion) {
            $maxVersion = $version
        }
    }
}

# Bump the version
if ($Major) {
    $newVersion = [Version]::new($maxVersion.Major + 1, 0, 0)
} elseif ($Minor) {
    $newVersion = [Version]::new($maxVersion.Major, $maxVersion.Minor + 1, 0)
} else {
    $newVersion = [Version]::new($maxVersion.Major, $maxVersion.Minor, $maxVersion.Build + 1)
}

Write-Host "Current highest version: $maxVersion" -ForegroundColor Cyan
Write-Host "New version: $newVersion" -ForegroundColor Green
if ($Test) {
    Write-Host "[TEST MODE - No files will be modified]" -ForegroundColor Yellow
}
Write-Host ""

# Update all .csproject files with AssemblyVersion
foreach ($project in $projects) {
    $content = Get-Content $project.FullName -Raw
    if ($content -match '<AssemblyVersion>(.*?)</AssemblyVersion>') {
        $oldVersion = $matches[1]
        if ($Test) {
            Write-Host "Would update: $($project.Name) ($oldVersion -> $newVersion)" -ForegroundColor Gray
        } else {
            $content = $content -replace '<AssemblyVersion>.*?</AssemblyVersion>', "<AssemblyVersion>$newVersion</AssemblyVersion>"
            Set-Content -Path $project.FullName -Value $content -NoNewline
            Write-Host "Updated: $($project.Name) ($oldVersion -> $newVersion)" -ForegroundColor Gray
        }
    }
}

# Update all package.json projects
foreach ($pkgPath in $frontendVersions.Keys) {
    $oldVersion = $frontendVersions[$pkgPath]
    if ($Test) {
        Write-Host "Would update: $pkgPath ($oldVersion -> $newVersion)" -ForegroundColor Gray
    } else {
        $pkgDir = Split-Path -Parent $pkgPath
        Push-Location $pkgDir
        npm version $newVersion.ToString() --no-git-tag-version --allow-same-version | Out-Null
        Pop-Location
        Write-Host "Updated: $pkgPath ($oldVersion -> $newVersion)" -ForegroundColor Gray
    }
}

Write-Host ""
if ($Test) {
    Write-Host "[TEST MODE] Would update all projects to version $newVersion" -ForegroundColor Yellow
} else {
    Write-Host "All projects updated to version $newVersion" -ForegroundColor Green
}