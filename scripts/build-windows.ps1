param(
    [switch]$FrameworkDependent
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$solutionPath = Join-Path $projectRoot "windows\AudioBridge.sln"
$testProject = Join-Path $projectRoot "windows\AudioBridge.Protocol.Tests\AudioBridge.Protocol.Tests.csproj"
$senderProject = Join-Path $projectRoot "windows\AudioBridge.Sender\AudioBridge.Sender.csproj"
$publishDirectory = Join-Path $projectRoot "artifacts\windows-x64"

dotnet restore $solutionPath
dotnet build $solutionPath --configuration Release --no-restore
dotnet test $testProject --configuration Release --no-build

$selfContained = if ($FrameworkDependent) { "false" } else { "true" }
dotnet publish $senderProject `
    --configuration Release `
    --runtime win-x64 `
    --self-contained $selfContained `
    --output $publishDirectory `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true

Write-Host "AudioBridge Sender is ready in $publishDirectory"
