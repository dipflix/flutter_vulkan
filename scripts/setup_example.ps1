# Copies compiled SPIR-V shaders from the main project into the Flutter example.
# Run this after `.\scripts\build_native.ps1` (which invokes glslc via CMake).
#
# Usage:
#   .\packages\flutter_vulkan\scripts\setup_example.ps1

$root = Resolve-Path "$PSScriptRoot\..\..\..\"
$src  = Join-Path $root "assets\shaders"
$dst  = Join-Path $PSScriptRoot "..\example\assets\shaders"

New-Item -ItemType Directory -Force $dst | Out-Null

foreach ($spv in @("mesh3d.vert.spv", "mesh3d.frag.spv")) {
    $from = Join-Path $src $spv
    if (-not (Test-Path $from)) {
        Write-Error "Missing shader: $from`nBuild the native libraries first: .\scripts\build_native.ps1"
        exit 1
    }
    Copy-Item $from $dst -Force
    Write-Host "  Copied $spv"
}

Write-Host "Shaders ready in $dst"
