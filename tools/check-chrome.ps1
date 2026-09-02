# Asserts that the shared page chrome stays identical across the site.
#
# The site has no build step and no partials: every page carries its own copy of the
# <header class="site"> nav and the <footer class="site"> link row. That is fine until
# someone adds a nav entry to five pages out of sixteen. This script is the cheap guard.
#
# Two groups are compared separately, because their relative paths legitimately differ:
#   - the root pages   (index.html, features.html, ...)   -> href="features.html"
#   - the guide pages  (guide/*.html)                     -> href="../features.html"
# The class="link active" marker is normalised away before comparing, since exactly one
# entry per page is supposed to carry it.
#
#   .\tools\check-chrome.ps1          # exit 0 = consistent, 1 = drift found
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Get-Block([string]$text, [string]$tag) {
    $m = [regex]::Match($text, "(?s)<$tag class=""site"">.*?</$tag>")
    if (-not $m.Success) { return $null }
    # one page's "active" link is another page's plain link
    return ($m.Value -replace '\s+class="link active"', ' class="link"')
}

$groups = @{
    'root'  = @(Get-ChildItem -Path $root -Filter *.html -File | Sort-Object Name)
    'guide' = @(Get-ChildItem -Path (Join-Path $root 'guide') -Filter *.html -File -ErrorAction SilentlyContinue | Sort-Object Name)
}

$problems = @()
foreach ($name in $groups.Keys | Sort-Object) {
    $files = $groups[$name]
    if ($files.Count -eq 0) { continue }

    foreach ($tag in @('header', 'footer')) {
        $baseline = $null
        $baseName = $null
        foreach ($f in $files) {
            $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
            $block = Get-Block $text $tag
            if ($null -eq $block) {
                $problems += "$name/$($f.Name): no <$tag class=""site""> block"
                continue
            }
            if ($null -eq $baseline) { $baseline = $block; $baseName = $f.Name; continue }
            if ($block -ne $baseline) {
                $problems += "$name/$($f.Name): <$tag> differs from $baseName"
            }
        }
    }
}

# Every root page must reach the guide. (Guide pages link it as a sibling index.html,
# which the header comparison above already holds identical, so they need no check here.)
foreach ($f in $groups['root']) {
    $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
    if ($text -notmatch 'href="guide/"') {
        $problems += "root/$($f.Name): no link to the guide"
    }
}

if ($problems.Count -gt 0) {
    Write-Host "chrome drift:" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

$total = ($groups.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
Write-Host "chrome consistent across $total pages" -ForegroundColor Green
exit 0
