param([string]$ReserveKg = '', [string]$Suffix = '', [string]$NoShots = '')
$exe = 'F:\DownloadedApps\GodotEngine\Godot_v4.7.2-stable_win64.exe'
$proj = 'F:\Projects\Space_Mission_design_Game\MissionArchitect_Godot4'
$out = Join-Path $proj ('tools\_probe_stdout' + $Suffix + '.txt')
$err = Join-Path $proj ('tools\_probe_stderr' + $Suffix + '.txt')
if (Test-Path $out) { Remove-Item $out }
if (Test-Path $err) { Remove-Item $err }
if ($ReserveKg -ne '') { $env:MA_BOOSTER_RESERVE_KG = $ReserveKg } else { Remove-Item Env:MA_BOOSTER_RESERVE_KG -ErrorAction SilentlyContinue }
if ($NoShots -ne '') { $env:MA_PROBE_NO_SHOTS = $NoShots } else { Remove-Item Env:MA_PROBE_NO_SHOTS -ErrorAction SilentlyContinue }
Start-Process -FilePath $exe -ArgumentList '--path', $proj, '-s', 'res://tools/_launch_physics_probe.gd' -RedirectStandardOutput $out -RedirectStandardError $err -Wait -NoNewWindow
$res = Join-Path $proj 'tools\_probe_result.txt'
Copy-Item $res ($res -replace '\.txt$', $Suffix + '.txt') -Force
Write-Host "PROBE SCRIPT DONE $Suffix"
