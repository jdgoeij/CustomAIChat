# Self-Hosted AI Stack

A comprehensive, self-hosted AI platform running on Docker — combining the best open-source tools for chat, model routing, observability, web search, image generation, speech-to-text, and document research.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       User Browser                           │
│       OpenWebUI (:3000)  │  Langfuse (:3001)  │  Open Notebook (:3002)
└───────────┬──────────────┴──────────────┬─────┴─────────────┘
            │                              │
┌───────────▼──────────────────────────────▼───────────────────┐
│                LiteLLM Proxy (:4000)                          │
│          Model Router / API Gateway / Budget Control           │
│     ┌──────────┬────────────┬────────────┬────────────┐      │
│     │Azure AOAI│  Ollama    │ OpenAI     │  ...more   │      │
│     │(cloud)   │  (local)   │ (cloud)    │  providers │      │
│     └──────────┴────────────┴────────────┴────────────┘      │
└──────────────────────────────────────────────────────────────┘
            │
┌───────────▼──────────────────────────────────────────────────┐
│  PostgreSQL │ Redis │ ClickHouse │ MinIO │ SearXNG │ Whisper │
│  ComfyUI │ Ollama │ Langfuse Worker │ Caddy (optional)       │
└──────────────────────────────────────────────────────────────┘
```

## Components

| Service | Purpose | Port | Compose File |
|---|---|---|---|
| **Open WebUI** | Chat frontend with RAG, tools, multi-modal | `3000` | core |
| **LiteLLM** | Model router (Azure, OpenAI, Ollama, 100+ providers) | `4000` | core |
| **Langfuse** | Observability, token/cost tracking, prompt tracing | `3001` | core |
| **SearXNG** | Private meta search engine for web search | `8080` | core |
| **PostgreSQL** | Database for LiteLLM + Langfuse | `5432` | core |
| **Redis** | Caching | `6379` | core |
| **ClickHouse** | Analytics DB for Langfuse | — | core |
| **MinIO** | S3-compatible storage for Langfuse | — | core |
| **Ollama** | Local LLM inference (GPU) | `11434` | gpu |
| **Whisper** | Speech-to-text (GPU) | `9000` | gpu |
| **ComfyUI** | Image generation / Stable Diffusion (GPU) | `8188` | gpu |
| **Open Notebook** | NotebookLM alternative — document research | `3002` | extras |
| **Caddy** | Reverse proxy with auto-HTTPS | `80/443` | extras |

## Prerequisites

- **Docker** ≥ 24.0 and **Docker Compose** ≥ 2.20
- **8 GB RAM** minimum for core stack (16+ GB recommended with GPU services)
- **NVIDIA GPU + NVIDIA Container Toolkit** (for GPU services only)
  - Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/

## Quick Start

### 1. Clone and configure

```bash
cd C:\Dev\Local\CustomAIChat

# Create your .env from the template
cp .env.example .env

# Edit .env — at minimum set:
#   - POSTGRES_PASSWORD (change from default)
#   - LITELLM_MASTER_KEY (generate a strong key)
#   - AZURE_API_BASE, AZURE_API_KEY (your Azure OpenAI credentials)
#   - LANGFUSE_SALT, LANGFUSE_ENCRYPTION_KEY (generate random strings)
#   - REDIS_PASSWORD, CLICKHOUSE_PASSWORD, MINIO_ROOT_PASSWORD
```

### 2. Start the stack

```powershell
# Core stack only (no GPU needed)
.\scripts\start.ps1 up core

# Core + GPU services (Ollama, Whisper, ComfyUI)
.\scripts\start.ps1 up gpu

# Everything (core + GPU + Open Notebook + Caddy)
.\scripts\start.ps1 up all
```

Or directly with Docker Compose:
```bash
# Core only
docker compose up -d

# Core + GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# All services
docker compose -f docker-compose.yml -f docker-compose.gpu.yml -f docker-compose.extras.yml up -d
```

### 3. First-run setup

1. **OpenWebUI** → http://localhost:3000
   - Create your admin account on first visit
   - All LiteLLM models will appear automatically in the model selector

2. **Langfuse** → http://localhost:3001
   - Create account and organization
   - Go to **Settings → API Keys** → create a new key pair
   - Copy the public key and secret key into your `.env`:
     ```
     LANGFUSE_PUBLIC_KEY=pk-lf-xxxxx
     LANGFUSE_SECRET_KEY=sk-lf-xxxxx
     ```
   - Restart LiteLLM: `docker compose restart litellm`

3. **Pull local models** (if using GPU stack):
   ```bash
   docker exec ai-ollama ollama pull llama3.2
   docker exec ai-ollama ollama pull mistral
   docker exec ai-ollama ollama pull codellama
   ```

4. **Download Stable Diffusion models** (if using ComfyUI):
   - Download model weights from [HuggingFace](https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0) or [CivitAI](https://civitai.com/)
   - Place `.safetensors` files in `./data/comfyui/models/checkpoints/`

5. **Configure image generation in OpenWebUI**:
   - Go to Admin → Settings → Images
   - Set engine to **ComfyUI**
   - Set API URL to `http://comfyui:8188`
   - For DALL-E: use LiteLLM proxy (models configured in `config/litellm/config.yaml`)

## Configuration

### Adding models to LiteLLM

Edit `config/litellm/config.yaml` and add entries to `model_list`:

```yaml
- model_name: azure/my-new-model
  litellm_params:
    model: azure/my-deployment-name
    api_base: os.environ/AZURE_API_BASE
    api_key: os.environ/AZURE_API_KEY
    api_version: os.environ/AZURE_API_VERSION
```

Then restart: `docker compose restart litellm`

### Azure OpenAI / AI Foundry

1. Create deployments in Azure AI Foundry or Azure OpenAI Studio
2. Set `AZURE_API_BASE` and `AZURE_API_KEY` in `.env`
3. Add each deployment to `config/litellm/config.yaml` using `azure/<deployment-name>` format
4. LiteLLM handles the Azure-specific API differences automatically

### Web Search (SearXNG)

Web search is pre-configured. In OpenWebUI:
- Click the **globe icon** (🌐) in the chat input to enable web search for a message
- SearXNG settings can be tuned in `config/searxng/settings.yml`

### Speech-to-Text (Whisper)

OpenWebUI includes built-in Whisper support. Click the **microphone icon** in chat to use it.

For the dedicated GPU Whisper service:
1. Start the GPU stack
2. In OpenWebUI Admin → Settings → Audio:
   - Set STT engine to **OpenAI**
   - Set API URL to `http://whisper:9000/v1`

### Observability (Langfuse)

All LLM calls through LiteLLM are automatically logged to Langfuse:
- **Traces**: See every LLM call, input/output, latency
- **Cost tracking**: Token usage and cost per model/user
- **Prompt management**: Version and compare prompts

Access at http://localhost:3001

### Reverse Proxy (Caddy)

To expose the stack externally with HTTPS:

1. Set your domain in `.env`: `CADDY_DOMAIN=ai.example.com`
2. Update `config/caddy/Caddyfile` — replace `localhost` with `{$CADDY_DOMAIN}`
3. Ensure ports 80/443 are open and DNS points to your server
4. Start extras: `.\scripts\start.ps1 up all`

Caddy automatically obtains Let's Encrypt certificates.

## Management

```powershell
# Check status
.\scripts\start.ps1 status

# View logs
.\scripts\start.ps1 logs openwebui
.\scripts\start.ps1 logs litellm

# Stop everything
.\scripts\start.ps1 down all

# Update images
.\scripts\start.ps1 pull all
.\scripts\start.ps1 up all

# Restart a single service
docker compose restart litellm
```

## File Structure

```
CustomAIChat/
├── .env                          # Your environment config (secrets — gitignored)
├── .env.example                  # Template with documentation
├── docker-compose.yml            # Core stack (always runs)
├── docker-compose.gpu.yml        # GPU services (Ollama, Whisper, ComfyUI)
├── docker-compose.extras.yml     # Extras (Open Notebook, Caddy)
├── config/
│   ├── litellm/config.yaml       # Model routing configuration
│   ├── searxng/settings.yml      # Search engine settings
│   ├── caddy/Caddyfile           # Reverse proxy routes
│   └── postgres/init-databases.sh
├── data/                         # Persistent volumes (gitignored)
├── models/                       # Model weights (gitignored)
├── scripts/
│   ├── start.ps1                 # PowerShell management script
│   └── start.sh                  # Bash management script
└── README.md                     # This file
```

## Troubleshooting

### Services won't start
```bash
docker compose logs -f          # Check all logs
docker compose ps -a            # See container status
```

### LiteLLM can't reach Langfuse
- Langfuse keys are generated after first login — make sure you've created them and added to `.env`
- Restart LiteLLM after updating keys: `docker compose restart litellm`

### OpenWebUI shows no models
- Check LiteLLM is running: `curl http://localhost:4000/health`
- Verify your Azure API key is correct in `.env`
- Check LiteLLM logs: `docker compose logs litellm`

### SearXNG returns 403
- Ensure `formats: [html, json]` is in `config/searxng/settings.yml`
- Restart: `docker compose restart searxng`

### GPU services fail to start
- Verify NVIDIA drivers: `nvidia-smi`
- Verify Container Toolkit: `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi`

## License

This stack configuration is provided as-is. Individual components have their own licenses:
- Open WebUI: MIT
- LiteLLM: MIT
- Langfuse: MIT
- SearXNG: AGPL-3.0
- Ollama: MIT
- ComfyUI: GPL-3.0
- Open Notebook: MIT
- Caddy: Apache 2.0
