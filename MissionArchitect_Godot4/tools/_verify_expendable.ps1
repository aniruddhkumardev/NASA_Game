$env:MA_PROBE_NO_SHOTS = '1'
$exe = 'F:\DownloadedApps\GodotEngine\Godot_v4.7.2-stable_win64.exe'
$proj = 'F:\Projects\Space_Mission_design_Game\MissionArchitect_Godot4'
& $exe --headless --path $proj -s 'res://tools/_launch_physics_probe.gd' 2>&1 | Select-Object -Last 4
Write-Host '--- RESULT FILE ---'
Get-Content (Join-Path $proj 'tools\_probe_result.txt')
