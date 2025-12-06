# AI Services Setup Guide

This guide covers the setup and configuration of all AI services in the Weekend Stack.

## 🧠 Service Overview

| Service | Port | GPU Required | Description |
|---------|------|--------------|-------------|
| Open WebUI | 3000 | No | Chat interface for Ollama/OpenAI models |
| SearXNG | 4000 | No | Privacy-focused metasearch engine |
| Stable Diffusion | 7861 | Yes | AUTOMATIC1111 WebUI for image generation |
| LocalAI | 8084 | Optional | OpenAI-compatible local LLM API server |
| AnythingLLM | 3003 | No | Document chat with RAG capabilities |
| Whisper | 9000 | Optional | OpenAI Whisper speech-to-text |
| WhisperX | 9001 | Yes | Enhanced speech-to-text with diarization |
| PrivateGPT | 8501 | Optional | Private document AI chat |
| LibreChat | 3080 | No | Multi-provider ChatGPT-like interface |
| ComfyUI | 8188 | Yes | Node-based image generation workflow |

## 🚀 Quick Start

### Start All AI Services (CPU Only)

```bash
docker compose --profile ai up -d
```

### Start GPU-Accelerated Services

```bash
docker compose --profile gpu up -d
```

### Start Everything

```bash
docker compose --profile ai --profile gpu up -d
```

## 📦 Individual Service Setup

### Open WebUI (Chat Interface)

Open WebUI provides a ChatGPT-like interface for Ollama and other LLM providers.

**Prerequisites:**
- Ollama running on host (port 11434)

**Configuration:**
```bash
# .env
OPENWEBUI_PORT=3000
OPENWEBUI_DOMAIN=chat.${BASE_DOMAIN}
WEBUI_SECRET_KEY=your-secret-key
OLLAMA_HOST=http://host.docker.internal:11434
```

**Access:** http://192.168.2.50:3000

**First-time Setup:**
1. Create an admin account on first visit
2. Open WebUI will auto-detect Ollama models
3. Configure additional providers in Settings > Admin > Connections

---

### LocalAI (Local LLM API)

LocalAI provides an OpenAI-compatible API for running local models.

**Configuration:**
```bash
# .env
LOCALAI_PORT=8084
LOCALAI_THREADS=4
LOCALAI_CONTEXT_SIZE=2048
LOCALAI_MEMORY_LIMIT=8g
```

**Access:** http://192.168.2.50:8084

**Model Installation:**
```bash
# Access container
docker exec -it localai bash

# Download models from the gallery
# Models are stored in /models volume
```

**API Usage:**
```bash
# List models
curl http://192.168.2.50:8084/v1/models

# Chat completion
curl http://192.168.2.50:8084/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-3.5-turbo",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

### AnythingLLM (Document Chat)

AnythingLLM provides RAG (Retrieval Augmented Generation) for chatting with your documents.

**Configuration:**
```bash
# .env
ANYTHINGLLM_PORT=3003
ANYTHINGLLM_MEMORY_LIMIT=2g
```

**Access:** http://192.168.2.50:3003

**Features:**
- Upload PDFs, Word docs, text files
- Create workspaces for different projects
- Connect to various LLM providers (Ollama, OpenAI, etc.)
- Vector database for document embeddings

---

### LibreChat (Multi-Provider Chat)

LibreChat provides a unified interface for multiple AI providers.

**Configuration:**
```bash
# .env
LIBRECHAT_PORT=3080
LIBRECHAT_CREDS_KEY=your-32-char-key
LIBRECHAT_CREDS_IV=your-16-char-iv
LIBRECHAT_JWT_SECRET=your-jwt-secret
LIBRECHAT_JWT_REFRESH_SECRET=your-refresh-secret

# Optional external providers
LIBRECHAT_OPENAI_API_KEY=sk-...
LIBRECHAT_ANTHROPIC_API_KEY=sk-ant-...
LIBRECHAT_GOOGLE_API_KEY=...
```

**Access:** http://192.168.2.50:3080

**Supported Providers:**
- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude)
- Google (Gemini)
- Local models via Ollama
- Azure OpenAI
- And more...

---

### Whisper (Speech-to-Text)

OpenAI Whisper for transcribing audio files.

**Configuration:**
```bash
# .env
WHISPER_PORT=9000
WHISPER_MODEL=base  # tiny, base, small, medium, large
WHISPER_MEMORY_LIMIT=4g
```

**Access:** http://192.168.2.50:9000

**API Usage:**
```bash
curl -X POST http://192.168.2.50:9000/asr \
  -F "audio_file=@recording.mp3" \
  -F "task=transcribe" \
  -F "language=en"
```

**Model Sizes:**
- `tiny`: 75MB, fastest, lower accuracy
- `base`: 140MB, good balance
- `small`: 460MB, better accuracy
- `medium`: 1.5GB, high accuracy
- `large`: 3GB, best accuracy (requires GPU)

---

### WhisperX (Enhanced Speech-to-Text)

WhisperX adds word-level timestamps and speaker diarization.

**Requirements:** NVIDIA GPU recommended

**Configuration:**
```bash
# .env
WHISPERX_PORT=9001
WHISPERX_MODEL=base
WHISPERX_MEMORY_LIMIT=8g
```

**Access:** http://192.168.2.50:9001

**Features:**
- Word-level timestamps
- Speaker diarization
- Better alignment than vanilla Whisper

---

### PrivateGPT (Private Document AI)

PrivateGPT allows private document querying without sending data to external APIs.

**Configuration:**
```bash
# .env
PRIVATEGPT_PORT=8501
PRIVATEGPT_MEMORY_LIMIT=4g
```

**Access:** http://192.168.2.50:8501

**Features:**
- 100% offline document processing
- No data leaves your server
- Supports PDFs, text files, and more

---

### Stable Diffusion WebUI (Image Generation)

AUTOMATIC1111's Stable Diffusion WebUI for AI image generation.

**Requirements:** NVIDIA GPU required

**Configuration:**
```bash
# .env
STABLE_DIFFUSION_PORT=7861
STABLE_DIFFUSION_MEMORY_LIMIT=8g
```

**Access:** http://192.168.2.50:7861

**Model Installation:**
1. Download models (.safetensors) from [Civitai](https://civitai.com) or [HuggingFace](https://huggingface.co)
2. Place in `files/stable-diffusion/models/Stable-diffusion/`
3. Refresh models in the WebUI dropdown

---

### ComfyUI (Node-based Image Generation)

ComfyUI provides a node-based workflow system for Stable Diffusion.

**Requirements:** NVIDIA GPU required

**Configuration:**
```bash
# .env
COMFYUI_PORT=8188
COMFYUI_MEMORY_LIMIT=8g
```

**Access:** http://192.168.2.50:8188

**Features:**
- Visual node-based workflow designer
- Highly customizable pipelines
- Support for ControlNet, LoRAs, etc.
- Share and import workflows

---

### SearXNG (Private Search)

SearXNG aggregates results from multiple search engines without tracking.

**Configuration:**
```bash
# .env
SEARXNG_PORT=4000
SEARXNG_SECRET_KEY=your-secret
SEARXNG_AUTH_USER=searx
SEARXNG_AUTH_PASSWORD=your-password
```

**Access:** http://192.168.2.50:4000

**Integration with Open WebUI:**
Open WebUI can use SearXNG for web-augmented AI responses:
1. Go to Settings > Admin > Connections
2. Enable Web Search
3. Set SearXNG URL: `http://searxng:8080`

---

## 🔗 Integration Examples

### Ollama + Open WebUI + SearXNG

The classic AI chat stack with web search:

```bash
# Ensure Ollama is running on host
ollama serve

# Start the AI stack
docker compose --profile ai up -d
```

### LocalAI as OpenAI Drop-in Replacement

Use LocalAI to replace OpenAI API calls:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://192.168.2.50:8084/v1",
    api_key="not-needed"  # LocalAI doesn't require API key
)

response = client.chat.completions.create(
    model="gpt-3.5-turbo",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

### N8N + AI Services

Connect n8n workflows to AI services:

```yaml
# HTTP Request node to LocalAI
URL: http://localai:8080/v1/chat/completions
Method: POST
Headers:
  Content-Type: application/json
Body:
  model: gpt-3.5-turbo
  messages:
    - role: user
      content: "{{ $json.prompt }}"
```

---

## 🔧 Troubleshooting

### GPU Not Detected

1. Ensure NVIDIA drivers are installed:
   ```bash
   nvidia-smi
   ```

2. Install nvidia-container-toolkit:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install -y nvidia-container-toolkit
   sudo systemctl restart docker
   ```

3. Verify Docker GPU access:
   ```bash
   docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
   ```

### Out of Memory Errors

- Reduce model sizes (e.g., use `base` instead of `large` for Whisper)
- Decrease `LOCALAI_CONTEXT_SIZE`
- Adjust memory limits in `.env`

### Connection Refused to Ollama

Ensure Ollama is listening on all interfaces:
```bash
OLLAMA_HOST=0.0.0.0:11434 ollama serve
```

Or use `host.docker.internal` from Docker containers.

### Services Not Starting

Check logs:
```bash
docker compose logs localai
docker compose logs anythingllm
# etc.
```

---

## 📚 Additional Resources

- [Open WebUI Documentation](https://docs.openwebui.com/)
- [LocalAI Documentation](https://localai.io/docs/)
- [AnythingLLM Documentation](https://docs.anythingllm.com/)
- [LibreChat Documentation](https://www.librechat.ai/docs)
- [Whisper GitHub](https://github.com/openai/whisper)
- [WhisperX GitHub](https://github.com/m-bain/whisperX)
- [PrivateGPT GitHub](https://github.com/zylon-ai/private-gpt)
- [Stable Diffusion WebUI](https://github.com/AUTOMATIC1111/stable-diffusion-webui)
- [ComfyUI GitHub](https://github.com/comfyanonymous/ComfyUI)
- [SearXNG Documentation](https://docs.searxng.org/)

---

## 🗺️ Port Reference

| Service | Local URL | Traefik Domain |
|---------|-----------|----------------|
| Open WebUI | http://192.168.2.50:3000 | chat.weekendcodeproject.dev |
| SearXNG | http://192.168.2.50:4000 | search.weekendcodeproject.dev |
| Stable Diffusion | http://192.168.2.50:7861 | sd.weekendcodeproject.dev |
| LocalAI | http://192.168.2.50:8084 | localai.weekendcodeproject.dev |
| AnythingLLM | http://192.168.2.50:3003 | anythingllm.weekendcodeproject.dev |
| Whisper | http://192.168.2.50:9000 | whisper.weekendcodeproject.dev |
| WhisperX | http://192.168.2.50:9001 | whisperx.weekendcodeproject.dev |
| PrivateGPT | http://192.168.2.50:8501 | privategpt.weekendcodeproject.dev |
| LibreChat | http://192.168.2.50:3080 | librechat.weekendcodeproject.dev |
| ComfyUI | http://192.168.2.50:8188 | comfyui.weekendcodeproject.dev |
