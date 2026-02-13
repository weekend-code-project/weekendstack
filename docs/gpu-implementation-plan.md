# GPU-Accelerated AI Stack Implementation Plan

> **Status:** Implementation Complete - Testing Required  
> **Created:** January 26, 2026  
> **Target:** Configure all AI services with shared GPU acceleration, .env-based VRAM allocation (8GB-94GB), bind-mounted model storage, and automatic minimal model downloads

## Overview

Configure 3 chat frontends (Open WebUI, LibreChat, AnythingLLM), 2 image generators (Stable Diffusion, ComfyUI), unified Ollama backend, and Immich ML to leverage shared GPU with automatic minimal model downloads for immediate testing capability within 8GB VRAM footprint.

**Default 8GB Configuration:** 1GB Ollama (qwen2.5:0.5b) + 6GB Stable Diffusion (SD 1.5) running simultaneously

---

## Step 1: GPU Configuration Variables in .env

Add comprehensive GPU and AI model configuration section to `.env`

### Tasks

- [x] Create new `GPU & AI SERVICES CONFIGURATION` section header
- [x] Add `GPU_ENABLE=true` toggle
- [x] Add `GPU_VRAM_DEFAULT=8g` documentation variable
- [x] Add `GPU_COUNT=1` for shared GPU mode
- [x] Add service memory limits:
  - [x] `OLLAMA_MEMORY_LIMIT=1g`
  - [x] `STABLE_DIFFUSION_MEMORY_LIMIT=6g`
  - [x] `COMFYUI_MEMORY_LIMIT=6g`
  - [x] `WHISPERX_MEMORY_LIMIT=4g`
  - [x] `DIFFRHYTHM_MEMORY_LIMIT=8g`
- [x] Add auto-download model configuration:
  - [x] `OLLAMA_AUTO_PULL_MODEL=qwen2.5:0.5b`
  - [x] `STABLE_DIFFUSION_AUTO_DOWNLOAD_MODEL=` (URL)
  - [x] `COMFYUI_AUTO_DOWNLOAD_MODEL=` (optional)
- [x] Add Immich GPU toggle:
  - [x] `IMMICH_GPU_ENABLE=false`
  - [x] `IMMICH_ML_MEMORY_LIMIT=2g`
- [x] Add VRAM tier configuration examples in comments (8GB, 16GB, 32GB, 94GB)

### Acceptance Criteria

- `.env` contains all GPU-related variables with sensible 8GB defaults
- Comments document configuration examples for different VRAM sizes
- Variables follow existing naming conventions in file

### Files

- [.env](../.env)

---

## Step 2: Bind-Mount AI Models to Files Directory

Replace Docker volumes with bind mounts for portable model storage

### Tasks

- [x] Create directory structure documentation:
  - `./files/ai-models/ollama/`
  - `./files/ai-models/stable-diffusion/`
  - `./files/ai-models/comfyui/`
  - `./files/ai-models/diffrhythm/`
  - `./files/ai-models/whisper/`
- [x] Update compose/docker-compose.ai.yml volume definitions:
  - [x] Replace `ollama-data` volume with bind mount
  - [x] Replace `stable-diffusion-models` and `stable-diffusion-data` with bind mounts
  - [x] Replace `comfyui-models` and `comfyui-data` with bind mounts
  - [x] Update WhisperX model path
  - [x] Update DiffRhythm model path
- [x] Add `.gitignore` entries for `files/ai-models/` (already covered by `files/`)
- [x] Update `files/README.md` with ai-models symlink instructions

### Acceptance Criteria

- All AI services use `./files/ai-models/` for model storage
- Models persist across container recreations
- Directory can be symlinked to network share

### Files

- [compose/docker-compose.ai.yml](../compose/docker-compose.ai.yml)
- [files/README.md](../files/README.md)
- [.gitignore](../.gitignore)

---

## Step 3: Containerize Ollama with GPU and Auto-Model Pull

Create containerized Ollama service replacing native host installation

### Tasks

- [x] Add `ollama` service to compose/docker-compose.ai.yml:
  - [x] Use `ollama/ollama:latest` image
  - [x] Configure shared GPU reservation (`count: 1, capabilities: [gpu]`)
  - [x] Set memory limit from `${OLLAMA_MEMORY_LIMIT:-1g}`
  - [x] Bind mount `./files/ai-models/ollama:/root/.ollama`
  - [x] Expose port 11434
  - [x] Add healthcheck
  - [x] Add Traefik labels
  - [x] Add Glance labels
- [x] Add `ollama-init` service for auto-model pull:
  - [x] Use same ollama image
  - [x] Run `ollama pull ${OLLAMA_AUTO_PULL_MODEL}` if model not exists
  - [x] Depend on `ollama` service being healthy
  - [x] One-shot container (restart: no)
- [x] Update dependent services to use `http://ollama:11434`:
  - [x] Open WebUI (`OLLAMA_BASE_URL`)
  - [x] AnythingLLM (`OLLAMA_BASE_PATH`)
  - [x] LibreChat (ollama endpoint)
  - [x] PrivateGPT (`PGPT_OLLAMA_API_BASE`)
- [x] Remove `extra_hosts: host.docker.internal` from dependent services
- [x] Update .env `OLLAMA_HOST` variable and comments

### Acceptance Criteria

- `docker compose --profile gpu up -d` starts Ollama container with GPU
- Ollama accessible at `http://ollama:11434` from other containers
- Minimal model auto-downloads on first start
- Chat frontends successfully connect to containerized Ollama

### Files

- [docker-compose.ai.yml](../docker-compose.ai.yml)
- [.env](../.env)

---

## Step 4: Remove LocalAI and Consolidate to Ollama

Simplify LLM backend to single Ollama service

### Tasks

- [x] Comment out `localai` service in docker-compose.ai.yml
- [x] Comment out `localai-gpu` service (already commented)
- [x] Remove or comment LocalAI-related variables from .env:
  - [x] Variables kept but service disabled
- [x] Update LibreChat configuration to use only Ollama endpoint
- [x] Remove `localai-models` volume references

### Acceptance Criteria

- LocalAI services do not start with any profile
- No orphaned volume references
- LibreChat uses only Ollama backend

### Files

- [docker-compose.ai.yml](../docker-compose.ai.yml)
- [.env](../.env)

---

## Step 5: Configure Image Generators with GPU and Auto-Download

Set up Stable Diffusion and ComfyUI with shared GPU and minimal model downloads

### Tasks

- [x] Update Stable Diffusion WebUI service:
  - [x] Verify GPU reservation uses `${STABLE_DIFFUSION_MEMORY_LIMIT:-6g}`
  - [x] Update model bind mount to `./files/ai-models/stable-diffusion`
  - [x] Add `--ckpt-dir` argument pointing to mounted models
- [x] Add Stable Diffusion init container for model download:
  - [x] Use wget/curl to download model if not exists
  - [x] Download `v1-5-pruned-emaonly.safetensors` from HuggingFace
  - [x] Run before main service starts
- [x] Update ComfyUI service:
  - [x] Verify GPU reservation uses `${COMFYUI_MEMORY_LIMIT:-6g}`
  - [x] Update model bind mount to `./files/ai-models/comfyui`
  - [x] Configure model paths via environment
- [x] Update DiffRhythm model paths to bind mount

### Acceptance Criteria

- Stable Diffusion starts with working SD 1.5 model automatically
- ComfyUI starts (models downloadable via web UI)
- Both services share GPU without conflicts at 8GB
- Models stored in `./files/ai-models/`

### Files

- [docker-compose.ai.yml](../docker-compose.ai.yml)

---

## Step 6: Conditional Immich ML GPU and Documentation

Add GPU toggle for Immich and create comprehensive setup documentation

### Tasks

- [x] Modify `immich-machine-learning` service:
  - [x] Keep CPU version as default
  - [x] Add `immich-machine-learning-gpu` service with GPU reservation
  - [x] Use profile `gpu-media` for GPU version
  - [x] Set memory limit from `${IMMICH_ML_MEMORY_LIMIT:-4g}`
- [ ] Update docs/ai-services-setup.md:
  - [ ] Document 8GB VRAM limitations (simultaneous LLM + image gen)
  - [ ] Add VRAM tier configurations table
  - [ ] Document model download commands
  - [ ] Add GPU monitoring section (`nvidia-smi`)
  - [ ] Add OOM troubleshooting guide

### Acceptance Criteria

- Immich ML can be GPU-accelerated via env toggle
- Documentation covers all VRAM tiers with specific configurations
- Users can follow docs to configure for their hardware

### Files

- [docker-compose.media.yml](../docker-compose.media.yml)
- [docs/ai-services-setup.md](../docs/ai-services-setup.md)

---

## Discovered Issues / Blockers

_Track issues found during implementation here_

- [ ] _None yet_

---

## Considerations (Address After Working)

### 1. Auto-download Implementation Approach

Use docker-compose `entrypoint` override with wrapper script that checks for model existence before downloading, or add dedicated init containers with `depends_on` conditions? Init containers keep services cleaner but require compose 3.8+ syntax. Entrypoint wrappers work universally but complicate service startup logs.

### 2. Model Download Failure Handling

If auto-download fails (network issues, disk space), should services fail to start or start without models and log errors? Starting without models allows manual intervention but creates confusing "service running but non-functional" state. Recommend fail-fast approach with clear error messages?

### 3. Hugging Face vs Direct Download for SD Models

Stable Diffusion models can download from HuggingFace CLI (requires token for some models) or direct URLs. Direct URLs are simpler but may have rate limits. Consider using CivitAI API or creating model download helper script that users can customize for their preferred model sources?

---

## Validation Checklist

After implementation, verify:

- [x] Docker compose files validate without errors
- [x] Directory structure created at `./files/ai-models/`
- [ ] `docker compose --profile gpu up -d` starts all GPU services
- [ ] `nvidia-smi` shows GPU memory allocated to containers
- [ ] Open WebUI can chat with qwen2.5:0.5b model
- [ ] Stable Diffusion WebUI can generate 512x512 images with SD 1.5
- [ ] Both services run simultaneously within 8GB VRAM
- [ ] Models persist in `./files/ai-models/` after container recreation
- [ ] Immich ML GPU toggle works when using `--profile gpu-media`

---

## Quick Start Commands

```bash
# 1. Verify GPU access
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi

# 2. Start GPU AI services (will auto-download models on first run)
docker compose --profile gpu up -d

# 3. Watch init containers for model downloads
docker compose logs -f ollama-init sd-model-init

# 4. Verify services are running
docker compose ps --profile gpu

# 5. Access services
# - Open WebUI: http://localhost:3000
# - Stable Diffusion: http://localhost:7861
# - Ollama API: http://localhost:11434

# 6. For Immich with GPU ML acceleration
docker compose --profile media --profile gpu-media up -d
```

---

## VRAM Configuration Reference

| VRAM | Ollama | SD/ComfyUI | Recommended Models | Use Case |
|------|--------|------------|-------------------|----------|
| **8GB** | 1g | 6g | qwen2.5:0.5b, SD 1.5 | Basic testing, 512x512 |
| **16GB** | 6g | 6g | llama3.2:3b, SDXL | Balanced workloads |
| **32GB** | 16g | 10g | llama3.1:8b, FLUX | Professional |
| **94GB** | 40g | 20g | llama3.1:70b, FLUX-dev | Workstation |

### 8GB Limitations

- Simultaneous LLM chat + image generation works but expect slower inference
- Image generation limited to 512x512 for reliable operation
- Run one image generator at a time (SD or ComfyUI, not both)
- Larger models will cause OOM errors
