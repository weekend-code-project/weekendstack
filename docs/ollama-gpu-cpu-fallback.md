# Ollama GPU/CPU Automatic Fallback Guide

**Last Updated:** January 26, 2026  
**Status:** ✅ Implemented

---

## Overview

The stack now includes automatic GPU/CPU fallback for Ollama, allowing seamless operation whether or not a GPU is available.

## How It Works

Two Ollama service definitions exist in [docker-compose.ai.yml](../docker-compose.ai.yml):

1. **`ollama`** - GPU-accelerated version (profile: `gpu`, `all`)
2. **`ollama-cpu`** - CPU fallback version (profile: `ai`)

Both use `container_name: ollama` so they're **mutually exclusive** - only one can run at a time. The Docker Compose profile determines which service starts.

---

## Usage

### With GPU Available

```bash
# Start GPU-accelerated Ollama
docker compose --profile gpu up -d

# Or start all services including GPU services
docker compose --profile all up -d
```

**Result:**
- Ollama (GPU) starts with NVIDIA GPU access
- 10-15x faster inference than CPU
- Shows as "Ollama (GPU)" in Glance

### Without GPU (CPU Fallback)

```bash
# Start CPU-only Ollama
docker compose --profile ai up -d
```

**Result:**
- Ollama (CPU) starts without GPU requirements
- Slower inference but fully functional
- Shows as "Ollama (CPU)" in Glance

---

## Verification

### Check which version is running:

```bash
# View service name and GPU status
docker inspect ollama --format 'Service: {{index .Config.Labels "com.docker.compose.service"}}
GPU Enabled: {{if .HostConfig.DeviceRequests}}Yes{{else}}No{{end}}'
```

**Expected output (GPU):**
```
Service: ollama
GPU Enabled: Yes
```

**Expected output (CPU):**
```
Service: ollama-cpu
GPU Enabled: No
```

### Test performance:

```bash
# Time a simple inference
time docker exec ollama ollama run qwen2.5:0.5b "Write a haiku"

# Get detailed metrics
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:0.5b",
  "prompt": "Write a haiku",
  "stream": false
}' | jq -r '"Tokens/s: " + (.eval_count / (.eval_duration / 1000000000) | tostring)'
```

**Performance expectations:**
- **GPU:** 30-50 tokens/s for small models (0.5B-3B)
- **CPU:** 2-10 tokens/s depending on model size

---

## Configuration

### Environment Variables

Both services use the same environment variables in `.env`:

```bash
# Ollama configuration
OLLAMA_PORT=11434
OLLAMA_MEMORY_LIMIT=4g           # Container RAM limit
FILES_BASE_DIR=./files           # Model storage location

# GPU configuration (only affects GPU service)
GPU_COUNT=1                      # Number of GPUs to allocate
```

### Model Storage

Both services share the same model storage volume:
```
./files/ai-models/ollama/
```

This means models downloaded in GPU mode are available in CPU mode and vice versa.

---

## Glance Dashboard Integration

Both Ollama services are now in the **Monitoring** group and hidden from the main service list:

- **Group:** Monitoring (renamed from "Monitoring" in Glance)
- **Hide:** Yes (only shown in Monitoring widget, not main list)
- **Icon:** Ollama logo
- **Description:** Shows "(GPU)" or "(CPU)" to indicate mode

Whisper is also moved to the Monitoring group for consistency.

### View in Glance

The Monitoring widget will show:
- **Ollama (GPU)** or **Ollama (CPU)** - depending on which is running
- **Whisper** - Speech-to-Text API
- Other monitoring services (Uptime Kuma, WUD, etc.)

---

## Switching Between GPU and CPU

To switch modes, stop and restart with a different profile:

### GPU → CPU

```bash
docker compose stop ollama
docker compose rm -f ollama
docker compose --profile ai up -d
```

### CPU → GPU

```bash
docker compose stop ollama
docker compose rm -f ollama
docker compose --profile gpu up -d
```

**Note:** No data loss - both services use the same model storage volume.

---

## Automatic Detection Script

For convenience, use this script to automatically detect GPU and start the appropriate service:

```bash
#!/bin/bash
# auto-start-ollama.sh

if nvidia-smi &> /dev/null; then
    echo "✓ GPU detected - starting Ollama (GPU)"
    docker compose --profile gpu up -d ollama
else
    echo "⚠ No GPU detected - starting Ollama (CPU)"
    docker compose --profile ai up -d ollama-cpu
fi

# Wait for health check
sleep 10
docker ps --format "{{.Names}}: {{.Status}}" | grep ollama
```

Save as `tools/auto-start-ollama.sh` and make executable:

```bash
chmod +x tools/auto-start-ollama.sh
./tools/auto-start-ollama.sh
```

---

## Troubleshooting

### Issue: Both services try to start

**Cause:** Using `--profile all` includes the `ai` profile which conflicts.

**Solution:** Use `--profile gpu` for GPU mode, or `--profile ai` for CPU-only mode.

### Issue: GPU service fails to start

**Cause:** NVIDIA drivers or Container Toolkit not installed.

**Solution:**
1. Verify GPU drivers: `nvidia-smi`
2. Check Docker GPU support: `docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi`
3. Fall back to CPU: `docker compose --profile ai up -d`

See [GPU Docker Setup Guide](./gpu-docker-setup.md) for full installation instructions.

### Issue: Models not appearing after switching modes

**Cause:** Container not using correct volume mount.

**Solution:**
```bash
# Verify volume mount
docker inspect ollama --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{end}}'

# Should show: ./files/ai-models/ollama -> /root/.ollama
```

### Issue: Ollama not showing in Glance

**Cause:** Glance needs to refresh to pick up new labels.

**Solution:**
```bash
# Restart Glance to refresh service discovery
docker compose restart glance
```

---

## Performance Comparison

Based on RTX 2000 Ada Generation (16GB VRAM):

| Model Size | GPU (tokens/s) | CPU (tokens/s) | Speedup |
|------------|----------------|----------------|---------|
| 0.5B       | 36.56          | 2.44           | 15x     |
| 3B         | ~25            | ~1.5           | ~17x    |
| 7B         | ~15            | ~0.8           | ~19x    |
| 13B        | ~8             | ~0.4           | ~20x    |

**Recommendation:** Use GPU whenever available for interactive workloads. CPU is acceptable for batch processing or testing.

---

## Related Documentation

- [GPU Docker Setup Guide](./gpu-docker-setup.md) - Full GPU installation and configuration
- [AI Services Setup](./ai-services-setup.md) - Configuring AI chat frontends
- [Services Guide](./services-guide.md) - Overview of all stack services

---

**Status:** Production Ready ✅  
**Tested On:** Ubuntu 24.04 LTS with NVIDIA RTX 2000 Ada Generation
