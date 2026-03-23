<#
.SYNOPSIS
    Start/stop the AI Stack with profile selection.

.DESCRIPTION
    Manages Docker Compose services for the self-hosted AI stack.

.PARAMETER Action
    Action to perform: up, down, status, logs, pull

.PARAMETER Profile
    Stack profile: core, gpu, extras, all

.EXAMPLE
    .\start.ps1 up core        # Start core services only
    .\start.ps1 up gpu         # Start core + GPU services
    .\start.ps1 up all         # Start everything
    .\start.ps1 down all       # Stop everything
    .\start.ps1 status         # Show running containers
    .\start.ps1 logs openwebui # Follow logs for a service
    .\start.ps1 pull all       # Pull latest images
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("up", "down", "status", "logs", "pull")]
    [string]$Action = "up",

    [Parameter(Position=1)]
    [string]$Profile = "core"
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot\..

function Get-ComposeFiles {
    param([string]$Prof)
    switch ($Prof) {
        "core"   { return @("-f", "docker-compose.yml") }
        "gpu"    { return @("-f", "docker-compose.yml", "-f", "docker-compose.gpu.yml") }
        "extras" { return @("-f", "docker-compose.yml", "-f", "docker-compose.extras.yml") }
        "all"    { return @("-f", "docker-compose.yml", "-f", "docker-compose.gpu.yml", "-f", "docker-compose.extras.yml") }
        default  { return @("-f", "docker-compose.yml") }
    }
}

try {
    switch ($Action) {
        "up" {
            Write-Host "Starting AI Stack [$Profile]..." -ForegroundColor Cyan
            $files = Get-ComposeFiles $Profile
            & docker compose @files up -d
            Write-Host ""
            Write-Host "Stack is starting! Access points:" -ForegroundColor Green
            Write-Host "  OpenWebUI:     http://localhost:3000" -ForegroundColor Yellow
            Write-Host "  Langfuse:      http://localhost:3001" -ForegroundColor Yellow
            Write-Host "  LiteLLM Admin: http://localhost:4000" -ForegroundColor Yellow
            Write-Host "  SearXNG:       http://localhost:8080" -ForegroundColor Yellow
            if ($Profile -in @("gpu", "all")) {
                Write-Host "  Ollama:        http://localhost:11434" -ForegroundColor Yellow
                Write-Host "  Whisper:       http://localhost:9000" -ForegroundColor Yellow
                Write-Host "  ComfyUI:       http://localhost:8188" -ForegroundColor Yellow
            }
            if ($Profile -in @("extras", "all")) {
                Write-Host "  Open Notebook: http://localhost:3002" -ForegroundColor Yellow
            }
        }
        "down" {
            Write-Host "Stopping AI Stack [$Profile]..." -ForegroundColor Cyan
            $files = Get-ComposeFiles $Profile
            & docker compose @files down
            Write-Host "Stack stopped." -ForegroundColor Green
        }
        "status" {
            & docker compose -f docker-compose.yml ps -a
        }
        "logs" {
            if ($Profile -and $Profile -ne "core") {
                & docker compose -f docker-compose.yml logs -f --tail=100 $Profile
            } else {
                & docker compose -f docker-compose.yml logs -f --tail=50
            }
        }
        "pull" {
            Write-Host "Pulling latest images for [$Profile]..." -ForegroundColor Cyan
            $files = Get-ComposeFiles $Profile
            & docker compose @files pull
            Write-Host "Images updated. Run '.\start.ps1 up $Profile' to apply." -ForegroundColor Green
        }
    }
} finally {
    Pop-Location
}
