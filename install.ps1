# Links the SlotFiller addon folder from this repo into the WoW retail AddOns
# folder as a directory junction, so edits here are live in the game after /reload.
# Run again to re-create the link. Remove with:  Remove-Item "<AddOns>\SlotFiller"
param(
    [string]$WowAddOns = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"
)

$source = Join-Path $PSScriptRoot "SlotFiller"
$target = Join-Path $WowAddOns "SlotFiller"

if (-not (Test-Path $source)) { throw "Addon source folder not found: $source" }
if (-not (Test-Path $WowAddOns)) { throw "WoW AddOns folder not found: $WowAddOns" }

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -eq "Junction") {
        Write-Host "Junction already exists: $target -> $($item.Target)"
        exit 0
    }
    throw "A real folder already exists at $target. Move it away first."
}

New-Item -ItemType Junction -Path $target -Target $source | Out-Null
Write-Host "Linked $target -> $source"
