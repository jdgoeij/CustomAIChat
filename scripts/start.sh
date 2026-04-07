#!/usr/bin/env bash
# =============================================================================
# AI Stack — Start/Stop Script
# =============================================================================
# Whole-stack:
#   ./scripts/start.sh up core       # Start core services only
#   ./scripts/start.sh up gpu        # Start core + ALL GPU services
#   ./scripts/start.sh up all        # Start everything
#   ./scripts/start.sh down all      # Stop everything
#   ./scripts/start.sh status        # Show running containers
#   ./scripts/start.sh logs openwebui # Follow logs for a service
#   ./scripts/start.sh pull all      # Pull latest images
#
# Per-service GPU control (recommended for 8 GB GPUs):
#   ./scripts/start.sh gpu-start ollama   # Start Ollama + local LiteLLM config
#   ./scripts/start.sh gpu-start whisper  # Start Whisper + enable STT
#   ./scripts/start.sh gpu-start comfyui  # Start ComfyUI
#   ./scripts/start.sh gpu-stop ollama    # Stop Ollama + restore cloud config
#   ./scripts/start.sh gpu-switch comfyui # Stop Ollama, start ComfyUI
#   ./scripts/start.sh gpu-status         # Show which GPU services are running
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-up}"
TARGET="${2:-core}"

# --- Compose file builders ---

get_compose_files() {
    case "$1" in
        core)   echo "-f docker-compose.yml" ;;
        gpu)    echo "-f docker-compose.yml -f docker-compose.gpu.yml" ;;
        extras) echo "-f docker-compose.yml -f docker-compose.extras.yml" ;;
        all)    echo "-f docker-compose.yml -f docker-compose.gpu.yml -f docker-compose.extras.yml" ;;
        *)      echo "-f docker-compose.yml" ;;
    esac
}

get_gpu_compose_files() {
    local base="-f docker-compose.yml"
    case "$1" in
        ollama)  echo "$base -f docker-compose.ollama.yml -f docker-compose.litellm-local.yml" ;;
        whisper) echo "$base -f docker-compose.whisper.yml" ;;
        comfyui) echo "$base -f docker-compose.comfyui.yml" ;;
    esac
}

# --- GPU helpers ---

is_gpu_service_running() {
    local container_name="$1"
    local running_state
    running_state=$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)
    [[ "$running_state" == "true" ]]
}

stop_gpu_service() {
    local svc="$1"
    case "$svc" in
        ollama)
            if is_gpu_service_running "ai-ollama"; then
                echo "  Stopping Ollama..."
                local files
                files=$(get_gpu_compose_files ollama)
                docker compose $files stop ollama
                docker compose $files rm -f ollama
                echo "  Restoring LiteLLM to cloud-only config..."
                docker compose -f docker-compose.yml up -d --force-recreate litellm
            fi
            ;;
        whisper)
            if is_gpu_service_running "ai-whisper"; then
                echo "  Stopping Whisper..."
                local files
                files=$(get_gpu_compose_files whisper)
                docker compose $files stop whisper
                docker compose $files rm -f whisper
                echo "  Restoring OpenWebUI without Whisper STT..."
                docker compose -f docker-compose.yml up -d --force-recreate openwebui
            fi
            ;;
        comfyui)
            if is_gpu_service_running "ai-comfyui"; then
                echo "  Stopping ComfyUI..."
                local files
                files=$(get_gpu_compose_files comfyui)
                docker compose $files stop comfyui
                docker compose $files rm -f comfyui
            fi
            ;;
    esac
}

start_gpu_service() {
    local svc="$1"
    case "$svc" in
        ollama)
            echo "  Starting Ollama + local LiteLLM config..."
            local files
            files=$(get_gpu_compose_files ollama)
            docker compose $files up -d --force-recreate litellm ollama
            ;;
        whisper)
            echo "  Starting Whisper + enabling STT in OpenWebUI..."
            local files
            files=$(get_gpu_compose_files whisper)
            docker compose $files up -d --force-recreate openwebui whisper
            ;;
        comfyui)
            echo "  Starting ComfyUI..."
            local files
            files=$(get_gpu_compose_files comfyui)
            docker compose $files up -d comfyui
            ;;
    esac
}

# --- Main ---

case "$ACTION" in

    # --- Whole-stack operations ---

    up)
        FILES=$(get_compose_files "$TARGET")
        echo "🚀 Starting AI Stack [$TARGET]..."
        docker compose $FILES up -d
        echo ""
        echo "✅ Stack is starting! Access points:"
        echo "   OpenWebUI:     http://localhost:3000"
        echo "   Langfuse:      http://localhost:3001"
        echo "   LiteLLM Admin: http://localhost:4000"
        echo "   SearXNG:       http://localhost:8080"
        if [[ "$TARGET" == "gpu" || "$TARGET" == "all" ]]; then
            echo "   Ollama:        http://localhost:11434"
            echo "   Whisper:       http://localhost:9000"
            echo "   ComfyUI:       http://localhost:8188"
        fi
        if [[ "$TARGET" == "extras" || "$TARGET" == "all" ]]; then
            echo "   Open Notebook: http://localhost:8502"
        fi
        ;;

    down)
        FILES=$(get_compose_files "$TARGET")
        echo "🛑 Stopping AI Stack [$TARGET]..."
        docker compose $FILES down
        echo "✅ Stack stopped."
        ;;

    status)
        FILES=$(get_compose_files "$TARGET")
        docker compose $FILES ps -a
        ;;

    logs)
        if [[ "$TARGET" != "core" ]]; then
            docker compose -f docker-compose.yml logs -f --tail=100 "$TARGET"
        else
            docker compose -f docker-compose.yml logs -f --tail=50
        fi
        ;;

    pull)
        FILES=$(get_compose_files "$TARGET")
        echo "📦 Pulling latest images for [$TARGET]..."
        docker compose $FILES pull
        echo "✅ Images updated. Run './scripts/start.sh up $TARGET' to apply."
        ;;

    # --- Per-service GPU operations ---

    gpu-start)
        if [[ "$TARGET" != "ollama" && "$TARGET" != "whisper" && "$TARGET" != "comfyui" ]]; then
            echo "Usage: $0 gpu-start {ollama|whisper|comfyui}"
            exit 1
        fi

        # Warn if starting a heavy GPU service while another heavy one is running
        if [[ "$TARGET" == "ollama" || "$TARGET" == "comfyui" ]]; then
            if [[ "$TARGET" == "ollama" ]] && is_gpu_service_running "ai-comfyui"; then
                echo "⚠️  WARNING: ComfyUI is already running. On an 8 GB GPU this will cause VRAM pressure."
                echo "   Consider: $0 gpu-switch $TARGET"
                echo ""
            elif [[ "$TARGET" == "comfyui" ]] && is_gpu_service_running "ai-ollama"; then
                echo "⚠️  WARNING: Ollama is already running. On an 8 GB GPU this will cause VRAM pressure."
                echo "   Consider: $0 gpu-switch $TARGET"
                echo ""
            fi
        fi

        start_gpu_service "$TARGET"
        echo ""
        echo "✅ $TARGET started."
        ;;

    gpu-stop)
        if [[ "$TARGET" != "ollama" && "$TARGET" != "whisper" && "$TARGET" != "comfyui" ]]; then
            echo "Usage: $0 gpu-stop {ollama|whisper|comfyui}"
            exit 1
        fi
        stop_gpu_service "$TARGET"
        echo "✅ $TARGET stopped."
        ;;

    gpu-switch)
        if [[ "$TARGET" != "ollama" && "$TARGET" != "whisper" && "$TARGET" != "comfyui" ]]; then
            echo "Usage: $0 gpu-switch {ollama|whisper|comfyui}"
            exit 1
        fi
        echo "🔄 Switching GPU to $TARGET..."

        # Stop the heavy services that conflict
        if [[ "$TARGET" == "ollama" ]]; then
            stop_gpu_service "comfyui"
        elif [[ "$TARGET" == "comfyui" ]]; then
            stop_gpu_service "ollama"
        fi
        # Whisper is lightweight — no need to stop others for it

        start_gpu_service "$TARGET"
        echo ""
        echo "✅ GPU switched to $TARGET."
        ;;

    gpu-status)
        echo "GPU services:"
        for pair in "Ollama:ai-ollama" "Whisper:ai-whisper" "ComfyUI:ai-comfyui"; do
            name="${pair%%:*}"
            container="${pair##*:}"
            if is_gpu_service_running "$container"; then
                echo "   $name: running ✅"
            else
                echo "   $name: stopped"
            fi
        done
        ;;

    *)
        echo "Usage: $0 {up|down|status|logs|pull|gpu-start|gpu-stop|gpu-switch|gpu-status} {core|gpu|extras|all|ollama|whisper|comfyui}"
        exit 1
        ;;
esac
