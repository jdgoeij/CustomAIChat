<#
.SYNOPSIS
    Start/stop the AI Stack with profile selection and per-service GPU control.

.DESCRIPTION
    Manages Docker Compose services for the self-hosted AI stack.
    GPU services (Ollama, Whisper, ComfyUI) can be started and stopped
    individually — ideal for 8 GB GPUs where running everything at once
    causes VRAM pressure.

.PARAMETER Action
    Action to perform:
      up, down, status, logs, pull          — whole-stack operations
      gpu-start, gpu-stop, gpu-switch       — per-service GPU control
      gpu-status                            — show running GPU services

.PARAMETER Profile
    Stack profile or GPU service name:
      core, gpu, extras, all                — for up/down/pull
      ollama, whisper, comfyui              — for gpu-start/gpu-stop/gpu-switch

.EXAMPLE
    .\start.ps1 up core            # Start core services only
    .\start.ps1 up gpu             # Start core + ALL GPU services
    .\start.ps1 up all             # Start everything
    .\start.ps1 gpu-start ollama   # Start Ollama (+ swap LiteLLM to local config)
    .\start.ps1 gpu-start whisper  # Start Whisper (+ enable STT in OpenWebUI)
    .\start.ps1 gpu-start comfyui  # Start ComfyUI
    .\start.ps1 gpu-stop ollama    # Stop Ollama (+ restore LiteLLM to cloud config)
    .\start.ps1 gpu-switch comfyui # Stop Ollama, then start ComfyUI
    .\start.ps1 gpu-status         # Show which GPU services are running
    .\start.ps1 down all           # Stop everything
    .\start.ps1 logs openwebui     # Follow logs for a service
    .\start.ps1 pull all           # Pull latest images
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("up", "down", "status", "logs", "pull", "gpu-start", "gpu-stop", "gpu-switch", "gpu-status")]
    [string]$Action = "up",

    [Parameter(Position=1)]
    [string]$Profile = "core"
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot\..

# --- Compose file builders ---

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

function Get-GpuComposeFiles {
    param([string]$Service)
    $base = @("-f", "docker-compose.yml")
    switch ($Service) {
        "ollama"  { return $base + @("-f", "docker-compose.ollama.yml", "-f", "docker-compose.litellm-local.yml") }
        "whisper" { return $base + @("-f", "docker-compose.whisper.yml") }
        "comfyui" { return $base + @("-f", "docker-compose.comfyui.yml") }
    }
}

# --- GPU helpers ---

function Test-GpuServiceRunning {
    param([string]$Container)
    $result = docker inspect --format "{{.State.Running}}" $Container 2>$null
    return ($result -eq "true")
}

function Stop-GpuService {
    param([string]$Service)
    switch ($Service) {
        "ollama" {
            if (Test-GpuServiceRunning "ai-ollama") {
                Write-Host "  Stopping Ollama..." -ForegroundColor Yellow
                $files = Get-GpuComposeFiles "ollama"
                & docker compose @files stop ollama
                & docker compose @files rm -f ollama
                # Restore LiteLLM to cloud-only config
                Write-Host "  Restoring LiteLLM to cloud-only config..." -ForegroundColor Yellow
                & docker compose -f docker-compose.yml up -d --force-recreate litellm
            }
        }
        "whisper" {
            if (Test-GpuServiceRunning "ai-whisper") {
                Write-Host "  Stopping Whisper..." -ForegroundColor Yellow
                $files = Get-GpuComposeFiles "whisper"
                & docker compose @files stop whisper
                & docker compose @files rm -f whisper
                # Restore OpenWebUI without STT override
                Write-Host "  Restoring OpenWebUI without Whisper STT..." -ForegroundColor Yellow
                & docker compose -f docker-compose.yml up -d --force-recreate openwebui
            }
        }
        "comfyui" {
            if (Test-GpuServiceRunning "ai-comfyui") {
                Write-Host "  Stopping ComfyUI..." -ForegroundColor Yellow
                $files = Get-GpuComposeFiles "comfyui"
                & docker compose @files stop comfyui
                & docker compose @files rm -f comfyui
            }
        }
    }
}

function Start-GpuService {
    param([string]$Service)
    switch ($Service) {
        "ollama" {
            Write-Host "  Starting Ollama + local LiteLLM config..." -ForegroundColor Cyan
            $files = Get-GpuComposeFiles "ollama"
            & docker compose @files up -d --force-recreate litellm ollama
        }
        "whisper" {
            Write-Host "  Starting Whisper + enabling STT in OpenWebUI..." -ForegroundColor Cyan
            $files = Get-GpuComposeFiles "whisper"
            & docker compose @files up -d --force-recreate openwebui whisper
        }
        "comfyui" {
            Write-Host "  Starting ComfyUI..." -ForegroundColor Cyan
            $files = Get-GpuComposeFiles "comfyui"
            & docker compose @files up -d comfyui
        }
    }
}

# --- Main ---

try {
    switch ($Action) {

        # --- Whole-stack operations ---

        "up" {
            $files = Get-ComposeFiles $Profile
            Write-Host "Starting AI Stack [$Profile]..." -ForegroundColor Cyan
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
                Write-Host "  Open Notebook: http://localhost:8502" -ForegroundColor Yellow
            }
        }

        "down" {
            $files = Get-ComposeFiles $Profile
            Write-Host "Stopping AI Stack [$Profile]..." -ForegroundColor Cyan
            & docker compose @files down
            Write-Host "Stack stopped." -ForegroundColor Green
        }

        "status" {
            $files = Get-ComposeFiles $Profile
            & docker compose @files ps -a
        }

        "logs" {
            if ($Profile -and $Profile -ne "core") {
                & docker compose -f docker-compose.yml logs -f --tail=100 $Profile
            } else {
                & docker compose -f docker-compose.yml logs -f --tail=50
            }
        }

        "pull" {
            $files = Get-ComposeFiles $Profile
            Write-Host "Pulling latest images for [$Profile]..." -ForegroundColor Cyan
            & docker compose @files pull
            Write-Host "Images updated. Run '.\start.ps1 up $Profile' to apply." -ForegroundColor Green
        }

        # --- Per-service GPU operations ---

        "gpu-start" {
            if ($Profile -notin @("ollama", "whisper", "comfyui")) {
                Write-Host "Usage: .\start.ps1 gpu-start {ollama|whisper|comfyui}" -ForegroundColor Red
                exit 1
            }

            # Warn if starting a heavy GPU service while another heavy one is running
            if ($Profile -in @("ollama", "comfyui")) {
                $other = if ($Profile -eq "ollama") { "ai-comfyui" } else { "ai-ollama" }
                $otherName = if ($Profile -eq "ollama") { "ComfyUI" } else { "Ollama" }
                if (Test-GpuServiceRunning $other) {
                    Write-Host "WARNING: $otherName is already running. On an 8 GB GPU this will cause VRAM pressure." -ForegroundColor Red
                    Write-Host "  Consider: .\start.ps1 gpu-switch $Profile" -ForegroundColor Yellow
                    Write-Host ""
                }
            }

            Start-GpuService $Profile
            Write-Host ""
            Write-Host "$Profile started." -ForegroundColor Green
        }

        "gpu-stop" {
            if ($Profile -notin @("ollama", "whisper", "comfyui")) {
                Write-Host "Usage: .\start.ps1 gpu-stop {ollama|whisper|comfyui}" -ForegroundColor Red
                exit 1
            }
            Stop-GpuService $Profile
            Write-Host "$Profile stopped." -ForegroundColor Green
        }

        "gpu-switch" {
            if ($Profile -notin @("ollama", "whisper", "comfyui")) {
                Write-Host "Usage: .\start.ps1 gpu-switch {ollama|whisper|comfyui}" -ForegroundColor Red
                exit 1
            }
            Write-Host "Switching GPU to $Profile..." -ForegroundColor Cyan

            # Stop the heavy services that conflict
            if ($Profile -eq "ollama") {
                Stop-GpuService "comfyui"
            } elseif ($Profile -eq "comfyui") {
                Stop-GpuService "ollama"
            }
            # Whisper is lightweight — no need to stop others for it

            Start-GpuService $Profile
            Write-Host ""
            Write-Host "GPU switched to $Profile." -ForegroundColor Green
        }

        "gpu-status" {
            Write-Host "GPU services:" -ForegroundColor Cyan
            $services = @(
                @{ Name = "Ollama";  Container = "ai-ollama" },
                @{ Name = "Whisper"; Container = "ai-whisper" },
                @{ Name = "ComfyUI"; Container = "ai-comfyui" }
            )
            foreach ($svc in $services) {
                if (Test-GpuServiceRunning $svc.Container) {
                    Write-Host "  $($svc.Name): running" -ForegroundColor Green
                } else {
                    Write-Host "  $($svc.Name): stopped" -ForegroundColor DarkGray
                }
            }
        }
    }
} finally {
    Pop-Location
}
