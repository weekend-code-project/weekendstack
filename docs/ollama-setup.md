# Ollama Setup Guide

Ollama is a unified LLM (Large Language Model) backend that provides a consistent API for running various AI models locally.

## Access URLs

| Type | URL |
|------|-----|
| Local | http://192.168.2.50:11434 |
| Public | https://ollama.weekendcodeproject.dev |

## Starting Ollama

### GPU Version (Recommended)
```bash
docker compose --profile gpu up -d ollama
```

### CPU Version (Fallback)
```bash
docker compose --profile ai up -d ollama-cpu
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_PORT` | 11434 | Host port for Ollama API |
| `OLLAMA_HOST` | http://ollama:11434 | Internal service URL |
| `OLLAMA_MEMORY_LIMIT` | 1g | Container memory limit (CPU version) |
| `OLLAMA_AUTO_PULL_MODEL` | qwen2.5:0.5b | Model to auto-download on first start |

## Storage Configuration

### Default: Local VM Storage

By default, Ollama stores AI models in local VM storage at `./files/ai-models/ollama`. Each model can be 400MB to 70GB+ in size, so storage can grow quickly.

### Advanced: NFS Network Storage

For large model collections, you can configure Ollama to use NFS storage (e.g., from Unraid NAS) to avoid consuming VM disk space. This is especially useful for:
- Multiple large models (7B, 13B, 33B+ parameter models)
- Shared model storage across multiple machines
- Preserving VM disk space for other services

#### Setup Steps

1. **Configure NFS Server** (e.g., Unraid)
   - Create NFS export: `/mnt/user/ollama-models`
   - Set permissions: `192.168.2.0/24(sec=sys,rw,no_subtree_check,all_squash,anonuid=99,anongid=100)`
   - Note: Read-write (`rw`) required for model downloads

2. **Configure Environment Variables** in `.env`:
   ```bash
   NFS_SERVER_IP=192.168.2.3
   NFS_OLLAMA_PATH=/mnt/user/ollama-models
   ```

3. **Edit docker-compose.ai.yml**:
   - Uncomment the NFS volume definition at the bottom:
     ```yaml
     ollama-nfs-models:
       driver: local
       driver_opts:
         type: nfs
         o: "addr=${NFS_SERVER_IP:-192.168.2.3},rw,nfsvers=4,nolock"
         device: ":${NFS_OLLAMA_PATH:-/mnt/user/ollama-models}"
     ```
   - In the ollama service volumes section, comment out the bind mount and uncomment the NFS volume:
     ```yaml
     # - type: bind
     #   source: ${FILES_BASE_DIR:-./files}/ai-models/ollama
     #   target: /root/.ollama
     #   bind:
     #     create_host_path: true
     - type: volume
       source: ollama-nfs-models
       target: /root/.ollama
     ```
   - Repeat for ollama-cpu service if using CPU version

4. **Restart Ollama**:
   ```bash
   docker compose down ollama
   docker compose --profile gpu up -d ollama
   ```

5. **Verify NFS Storage**:
   ```bash
   docker compose exec ollama ls -la /root/.ollama
   docker compose exec ollama du -sh /root/.ollama/models/*
   ```

#### Troubleshooting NFS

- **"Permission denied"**: Verify NFS export has `rw` permissions
- **"Slow model loading"**: NFS may be slower than local storage for model loading; ensure good network connection
- **"No such file or directory"**: Check `NFS_OLLAMA_PATH` matches your NFS export path

### Performance Considerations

- **Model Loading**: NFS storage may be slightly slower for initial model loading compared to local NVMe storage
- **Inference Speed**: Once loaded into memory/VRAM, inference performance is identical (models run in RAM)
- **Network**: Ensure gigabit+ connection between Docker host and NFS server for best performance

## Managing Models

### List Available Models
```bash
docker compose exec ollama ollama list
```

### Pull a Model
```bash
docker compose exec ollama ollama pull llama3.1:8b
docker compose exec ollama ollama pull qwen2.5:14b
docker compose exec ollama ollama pull codellama:13b
```

### Delete a Model
```bash
docker compose exec ollama ollama rm llama3.1:8b
```

### Check Model Size
```bash
docker compose exec ollama du -sh /root/.ollama/models/*
```

## Popular Models

| Model | Size | RAM Required | Use Case |
|-------|------|--------------|----------|
| qwen2.5:0.5b | ~400MB | 2GB | Testing, minimal systems |
| phi3:mini | ~2GB | 4GB | Quick chat, code completion |
| llama3.1:8b | ~4.7GB | 8GB | General chat, assistant |
| qwen2.5:14b | ~9GB | 16GB | Advanced reasoning |
| codellama:13b | ~7.5GB | 16GB | Code generation |
| llama3.1:70b | ~40GB | 64GB+ | Professional grade |

## Chat Interfaces

Ollama provides the backend API. Connect a frontend:

- **Open WebUI** - Recommended ChatGPT-like interface
- **LibreChat** - Multi-provider chat
- **AnythingLLM** - Document chat with RAG

See [ai-services-setup.md](ai-services-setup.md) for configuring chat interfaces.

## API Usage

Test the Ollama API directly:

```bash
# Generate a response
curl http://192.168.2.50:11434/api/generate -d '{
  "model": "qwen2.5:0.5b",
  "prompt": "Why is the sky blue?",
  "stream": false
}'

# Chat completion
curl http://192.168.2.50:11434/api/chat -d '{
  "model": "llama3.1:8b",
  "messages": [
    {"role": "user", "content": "Hello!"}
  ],
  "stream": false
}'
```

## Troubleshooting

### Check Ollama Status
```bash
docker compose exec ollama ollama list
docker logs ollama
```

### GPU Not Detected
```bash
# Verify GPU is available
docker compose exec ollama nvidia-smi

# If command fails, check GPU passthrough configuration
# See docs/gpu-docker-setup.md
```

### Out of Memory
- Reduce model size (try smaller parameter models)
- Increase `OLLAMA_MEMORY_LIMIT` in .env
- Use CPU version for smaller models if GPU VRAM is limited

### Model Download Slow
- Large models (7B+) can take 10-30 minutes on slower connections
- Check network speed: `docker compose exec ollama speedtest` (if speedtest-cli installed)
- Consider downloading models during off-hours

## Updating Ollama

```bash
docker compose pull ollama
docker compose up -d ollama
```

Existing models are preserved (stored in volume/NFS).
