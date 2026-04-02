#!/usr/bin/env bash
# =============================================================================
# AI Stack — Start/Stop Script
# =============================================================================
# Usage:
#   ./scripts/start.sh up core       # Start core services only
#   ./scripts/start.sh up gpu        # Start core + GPU services
#   ./scripts/start.sh up all        # Start everything
#   ./scripts/start.sh down all      # Stop everything
#   ./scripts/start.sh status        # Show running containers
#   ./scripts/start.sh logs openwebui # Follow logs for a service
#   ./scripts/start.sh pull all      # Pull latest images
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-up}"
PROFILE="${2:-core}"

get_compose_files() {
    case "$1" in
        core)   echo "-f docker-compose.yml" ;;
        gpu)    echo "-f docker-compose.yml -f docker-compose.gpu.yml" ;;
        extras) echo "-f docker-compose.yml -f docker-compose.extras.yml" ;;
        all)    echo "-f docker-compose.yml -f docker-compose.gpu.yml -f docker-compose.extras.yml" ;;
        *)      echo "-f docker-compose.yml" ;;
    esac
}

FILES=$(get_compose_files "$PROFILE")

case "$ACTION" in
    up)
        echo "🚀 Starting AI Stack [$PROFILE]..."
        docker compose $FILES up -d
        echo ""
        echo "✅ Stack is starting! Access points:"
        echo "   OpenWebUI:     http://localhost:3000"
        echo "   Langfuse:      http://localhost:3001"
        echo "   LiteLLM Admin: http://localhost:4000"
        echo "   SearXNG:       http://localhost:8080"
        if [[ "$PROFILE" == "gpu" || "$PROFILE" == "all" ]]; then
            echo "   Ollama:        http://localhost:11434"
            echo "   Whisper:       http://localhost:9000"
            echo "   ComfyUI:       http://localhost:8188"
        fi
        if [[ "$PROFILE" == "extras" || "$PROFILE" == "all" ]]; then
            echo "   Open Notebook: http://localhost:8502"
        fi
        ;;
    down)
        echo "🛑 Stopping AI Stack [$PROFILE]..."
        docker compose $FILES down
        echo "✅ Stack stopped."
        ;;
    status)
        docker compose $FILES ps -a
        ;;
    logs)
        if [[ "$PROFILE" != "core" ]]; then
            docker compose -f docker-compose.yml logs -f --tail=100 "$PROFILE"
        else
            docker compose -f docker-compose.yml logs -f --tail=50
        fi
        ;;
    pull)
        echo "📦 Pulling latest images for [$PROFILE]..."
        docker compose $FILES pull
        echo "✅ Images updated. Run './scripts/start.sh up $PROFILE' to apply."
        ;;
    *)
        echo "Usage: $0 {up|down|status|logs|pull} {core|gpu|extras|all}"
        exit 1
        ;;
esac
