# GPU Setup Guide for Docker and VM

> **Created:** January 26, 2026  
> **System:** Ubuntu 24.04 LTS (Noble Numbat)  
> **GPU:** NVIDIA RTX 2000 Ada Generation

This guide covers setting up NVIDIA GPU support for Docker containers in a VM environment with PCI passthrough.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Verify GPU Passthrough](#verify-gpu-passthrough)
3. [Install NVIDIA Drivers](#install-nvidia-drivers)
4. [Install NVIDIA Container Toolkit](#install-nvidia-container-toolkit)
5. [Configure Docker for GPU](#configure-docker-for-gpu)
6. [Verification](#verification)
7. [Troubleshooting](#troubleshooting)
8. [Performance Tuning](#performance-tuning)

---

## Prerequisites

### Hardware Requirements

- NVIDIA GPU with compute capability 3.5 or higher
- Hypervisor with PCI passthrough support (Proxmox, ESXi, KVM, etc.)
- Sufficient system RAM (8GB minimum, 16GB+ recommended)
- Sufficient VRAM for your workloads

### Software Requirements

- Ubuntu 24.04 LTS (or compatible Debian-based distribution)
- Docker Engine 19.03 or later
- Kernel 5.x or later
- Root or sudo access

### VM Configuration

Ensure your VM has:
- **PCI passthrough enabled** for the NVIDIA GPU
- **IOMMU enabled** in BIOS/hypervisor settings
- **Sufficient resources** allocated (CPU cores, RAM)

---

## Verify GPU Passthrough

Before installing drivers, verify the GPU is visible to the VM.

### 1. Check PCI Devices

```bash
lspci | grep -i nvidia
```

**Expected output:**
```
01:00.0 VGA compatible controller: NVIDIA Corporation AD107GL [RTX 2000 Ada Generation] (rev a1)
02:00.0 Audio device: NVIDIA Corporation Device 22be (rev a1)
```

If you see NVIDIA devices, passthrough is working. ✅

### 2. Check Kernel Modules

```bash
lsmod | grep nouveau
```

If `nouveau` (open-source driver) is loaded, it needs to be blacklisted:

```bash
# Create blacklist file
sudo tee /etc/modprobe.d/blacklist-nouveau.conf <<EOF
blacklist nouveau
options nouveau modeset=0
EOF

# Update initramfs
sudo update-initramfs -u

# Reboot required
sudo reboot
```

---

## Install NVIDIA Drivers

### 1. Update System Packages

```bash
sudo apt-get update
sudo apt-get upgrade -y
```

### 2. Determine Driver Version

Check recommended driver for your GPU:

```bash
ubuntu-drivers devices
```

**For RTX 2000 Ada Generation, use driver 570 or later.**

### 3. Install NVIDIA Drivers

#### Option A: Automatic Installation (Recommended)

```bash
sudo apt-get install -y nvidia-driver-570 nvidia-utils-570
```

#### Option B: Manual Selection

```bash
# Search available drivers
apt search nvidia-driver

# Install specific version
sudo apt-get install -y nvidia-driver-<version>
```

### 4. Reboot System

**Critical:** Drivers require a reboot to load kernel modules.

```bash
sudo reboot
```

### 5. Verify Driver Installation

After reboot:

```bash
nvidia-smi
```

**Expected output:**
```
+-----------------------------------------------------------------------------------------+
| NVIDIA-SMI 570.211.01             Driver Version: 570.211.01     CUDA Version: 12.8     |
|-----------------------------------------+------------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id          Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |           Memory-Usage | GPU-Util  Compute M. |
|                                         |                        |               MIG M. |
|=========================================+========================+======================|
|   0  NVIDIA RTX 2000 Ada ...        Off |   00000000:01:00.0 Off |                  N/A |
| 30%   35C    P8              5W /   70W |       0MiB /  16380MiB |      0%      Default |
|                                         |                        |                  N/A |
+-----------------------------------------+------------------------+----------------------+
```

If you see GPU information, drivers are installed correctly. ✅

---

## Install NVIDIA Container Toolkit

The NVIDIA Container Toolkit allows Docker containers to access GPU hardware.

### 1. Add NVIDIA Repository GPG Key

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
```

### 2. Add NVIDIA Repository

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
```

### 3. Update Package List

```bash
sudo apt-get update
```

### 4. Install NVIDIA Container Toolkit

```bash
sudo apt-get install -y nvidia-container-toolkit
```

**Expected output:**
```
The following NEW packages will be installed:
  libnvidia-container-tools libnvidia-container1 nvidia-container-toolkit
  nvidia-container-toolkit-base
```

---

## Configure Docker for GPU

### 1. Configure Docker Runtime

```bash
sudo nvidia-ctk runtime configure --runtime=docker
```

**Expected output:**
```
INFO[0000] Config file does not exist; using empty config 
INFO[0000] Wrote updated config to /etc/docker/daemon.json 
INFO[0000] It is recommended that docker daemon be restarted.
```

This creates/updates `/etc/docker/daemon.json` with:

```json
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia"
}
```

### 2. Restart Docker Daemon

```bash
sudo systemctl restart docker
```

### 3. Verify Docker Service

```bash
sudo systemctl status docker
```

Ensure Docker is running (green "active" status).

---

## Verification

### 1. Test GPU Access in Container

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

**Expected output:** Same `nvidia-smi` output as on the host.

If you see GPU information inside the container, setup is complete. ✅

### 2. Authenticate with Docker Hub (Recommended)

To avoid Docker Hub rate limits when pulling images, authenticate with your Docker Hub account:

```bash
docker login -u your-username
```

**Important:** Docker Hub requires a **Personal Access Token (PAT)**, not your account password.

**Create a Personal Access Token:**

1. Go to https://hub.docker.com/settings/security
2. Click "New Access Token"
3. Give it a name (e.g., "weekend-stack")
4. Select permissions:
   - **Read, Write, Delete** (full access)
   - **Read** only (if you only need to pull images)
5. Click "Generate"
6. **Copy the token** (it will only be shown once!)
7. When `docker login` prompts for password, paste the PAT

**Verify authentication:**
```bash
cat ~/.docker/config.json
```

Should show your authenticated registry with a token.

**Rate limits:**
- Anonymous users: 100 pulls per 6 hours
- Authenticated free accounts: 200 pulls per 6 hours
- Pro/Team accounts: Higher limits

### 3. Test with Ollama (AI Workload)

```bash
docker run --rm --gpus all nvidia/cuda:12.0-devel bash -c \
  "apt-get update && apt-get install -y cuda-samples-12-0 && \
   cd /usr/local/cuda/samples/1_Utilities/deviceQuery && \
   make && ./deviceQuery"
```

**Expected:** Device query should show your GPU details.

### 3. Test with Ollama (AI Workload)

```bash
docker run --rm --gpus all -p 11434:11434 ollama/ollama
```

Open another terminal:

```bash
curl http://localhost:11434/api/tags
```

Should return: `{"models":[]}`

---

## Troubleshooting

### Issue: `nvidia-smi` not found after reboot

**Cause:** Drivers not loaded or installation failed.

**Solution:**
```bash
# Check driver installation
dpkg -l | grep nvidia-driver

# Reinstall if needed
sudo apt-get install --reinstall nvidia-driver-570

# Check kernel modules
lsmod | grep nvidia

# Force module load
sudo modprobe nvidia

# Reboot
sudo reboot
```

### Issue: `nvidia-smi` shows "Failed to initialize NVML"

**Cause:** Driver/kernel mismatch or nouveau conflict.

**Solution:**
```bash
# Verify nouveau is blacklisted
cat /etc/modprobe.d/blacklist-nouveau.conf

# Check for nouveau in use
lsmod | grep nouveau

# If nouveau is loaded:
sudo update-initramfs -u
sudo reboot
```

### Issue: Docker can't find GPU (`--gpus all` fails)

**Cause:** NVIDIA Container Toolkit not configured properly.

**Solution:**
```bash
# Reinstall toolkit
sudo apt-get install --reinstall nvidia-container-toolkit

# Reconfigure Docker
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker
sudo systemctl restart docker

# Test again
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

### Issue: `Error response from daemon: could not select device driver "nvidia"`

**Cause:** Docker daemon not configured for NVIDIA runtime.

**Solution:**
```bash
# Check daemon.json exists
cat /etc/docker/daemon.json

# Should contain nvidia runtime config
# If missing, reconfigure:
sudo nvidia-ctk runtime configure --runtime=docker

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### Issue: GPU memory errors or OOM (Out of Memory)

**Cause:** Insufficient VRAM for workload.

**Solution:**
```bash
# Check GPU memory usage
nvidia-smi

# Reduce model size or batch size in application
# For Ollama, use smaller models:
docker exec ollama ollama pull qwen2.5:0.5b  # 400MB instead of larger models

# For Stable Diffusion, reduce resolution or use --medvram flag
```

### Issue: Performance degradation in VM vs bare metal

**Cause:** Normal overhead from virtualization.

**Expected performance:**
- PCIe passthrough: ~95-98% of bare metal performance
- vGPU/GRID: ~90-95% of bare metal performance

**Optimization:**
```bash
# Ensure CPU pinning in hypervisor
# Allocate dedicated CPU cores to VM
# Enable huge pages
# Disable power management in BIOS for consistent performance
```

---

## Performance Tuning

### 1. Enable Persistence Mode (Host)

Keeps GPU initialized between runs:

```bash
sudo nvidia-smi -pm 1
```

### 2. Set Power Limit (Optional)

For consistent performance vs. power saving:

```bash
# Check current power limit
nvidia-smi -q -d POWER

# Set power limit (example: 70W for RTX 2000)
sudo nvidia-smi -pl 70
```

### 3. Monitor GPU Utilization

```bash
# Real-time monitoring
watch -n 1 nvidia-smi

# GPU utilization over time
nvidia-smi dmon -s pucvmet
```

### 4. Docker Compose GPU Configuration

In `docker-compose.yml`, allocate GPU resources:

```yaml
services:
  ollama:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
        limits:
          memory: 4g  # Container RAM limit
```

**VRAM is automatically managed** - no need to specify VRAM limits in Docker.

---

## Docker Compose GPU Examples

### Shared GPU Access (Default)

All containers share the GPU:

```yaml
services:
  service1:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
  
  service2:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### Specific GPU Selection (Multi-GPU)

```yaml
services:
  service1:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['0']  # First GPU
              capabilities: [gpu]
  
  service2:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ['1']  # Second GPU
              capabilities: [gpu]
```

---

## Useful Commands Reference

```bash
# Check GPU info
nvidia-smi
lspci | grep -i nvidia

# Check driver version
nvidia-smi --query-gpu=driver_version --format=csv
cat /proc/driver/nvidia/version

# Check CUDA version
nvcc --version  # If CUDA toolkit installed

# List Docker GPUs
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi -L

# Monitor GPU in real-time
watch -n 1 nvidia-smi

# Check Docker daemon GPU config
cat /etc/docker/daemon.json

# Restart Docker
sudo systemctl restart docker

# View Docker GPU logs
journalctl -u docker --since "5 minutes ago" | grep -i gpu
```

---

## Hardware-Specific Notes

### NVIDIA RTX 2000 Ada Generation

- **Architecture:** Ada Lovelace
- **CUDA Cores:** 2816
- **VRAM:** 16GB GDDR6
- **TDP:** 70W
- **Compute Capability:** 8.9
- **Recommended Driver:** 570+ (supports Ada architecture)
- **Ideal for:** AI inference, small-to-medium model training, image generation

### VRAM Allocation Guidelines

| VRAM | Recommended Workloads |
|------|----------------------|
| 8GB | Small LLMs (7B params), SD 1.5, basic inference |
| 16GB | Medium LLMs (13B params), SDXL, concurrent services |
| 24GB+ | Large LLMs (30B+ params), FLUX, production workloads |

**Your RTX 2000 (16GB)** is ideal for:
- Multiple small models simultaneously
- Single medium-sized LLM
- SDXL image generation with breathing room
- Development and testing workloads

---

## Next Steps

After completing this setup:

1. ✅ **Reboot the system** to activate drivers
2. ✅ **Verify GPU with `nvidia-smi`**
3. ✅ **Test Docker GPU access**
4. ✅ **Start AI services:** `docker compose --profile all up -d`
5. ✅ **Monitor GPU usage** while running workloads

---

## Performance Benchmarks

Real-world performance data for AI models on this hardware.

### Hardware Configuration

- **GPU:** NVIDIA RTX 2000 Ada Generation (16GB VRAM)
- **CPU:** (VM host CPU with passthrough)
- **RAM:** (VM allocated RAM)
- **Driver:** nvidia-driver-570

### Benchmark Methodology

All benchmarks use the same test methodology:
- **Prompt:** "Tell me a short story"
- **Temperature:** Default (0.8)
- **Context Length:** Default (2048)
- **Batch Size:** Default
- **No streaming** (measured full response generation)

### LLM Inference Performance

| Model | Mode | Response Token/s | Prompt Token/s | Total Duration | Prompt Tokens | Completion Tokens | Notes |
|-------|------|------------------|----------------|----------------|---------------|-------------------|-------|
| qwen2.5:0.5b | CPU | 2.44 | 211.73 | 2m 47s | 34 | 408 | Baseline CPU performance |
| qwen2.5:0.5b | GPU | 36.56 | 110.94 | 12s | 34 | 408 | **15x speedup overall** |
| llama3.2:3b | CPU | _TBD_ | _TBD_ | _TBD_ | - | - | Larger model test |
| llama3.2:3b | GPU | _TBD_ | _TBD_ | _TBD_ | - | - | Expected 5-10x speedup |

### Image Generation Performance

| Model | Mode | Resolution | Steps | Time | Iterations/s | VRAM Used | Notes |
|-------|------|------------|-------|------|--------------|-----------|-------|
| SD 1.5 | GPU | 512x512 | 20 | _TBD_ | _TBD_ | _TBD_ | Standard quality |
| SD 1.5 | GPU | 768x768 | 20 | _TBD_ | _TBD_ | _TBD_ | High quality |
| SDXL | GPU | 1024x1024 | 20 | _TBD_ | _TBD_ | _TBD_ | Ultra quality |

### How to Benchmark

#### Ollama Models

```bash
# Run inference and get detailed metrics
time docker exec ollama ollama run qwen2.5:0.5b "Tell me a short story"

# Get detailed performance metrics
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen2.5:0.5b",
  "prompt": "Tell me a short story",
  "stream": false
}' | jq '.prompt_eval_duration, .eval_duration, .eval_count'
```

Response includes:
- `prompt_eval_duration`: Time to process prompt (nanoseconds)
- `eval_duration`: Time to generate response (nanoseconds)
- `eval_count`: Number of tokens generated
- Calculate tokens/s: `eval_count / (eval_duration / 1000000000)`

#### Stable Diffusion

```bash
# Monitor generation time in WebUI
# VRAM usage:
nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits

# Or via API
curl -X POST http://localhost:7861/sdapi/v1/txt2img \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "a beautiful landscape",
    "steps": 20,
    "width": 512,
    "height": 512
  }'
```

### Performance Expectations

Based on RTX 2000 Ada Generation specs:

#### LLM Inference (GPU)

| Model Size | Expected Token/s | VRAM Usage | Notes |
|------------|------------------|------------|-------|
| 0.5B - 1B | 50-100 | 1-2 GB | Very fast, real-time chat |
| 3B - 7B | 20-40 | 3-6 GB | Fast, good quality |
| 13B | 10-20 | 10-12 GB | Moderate speed, high quality |
| 30B+ | <10 | >14 GB | Slow, requires optimization |

#### Image Generation (GPU)

| Model | Resolution | Expected Time | VRAM Usage |
|-------|------------|---------------|------------|
| SD 1.5 | 512x512 | 2-4s | 2-3 GB |
| SD 1.5 | 768x768 | 5-8s | 3-4 GB |
| SDXL | 1024x1024 | 8-15s | 6-8 GB |
| FLUX | 1024x1024 | 15-30s | 10-14 GB |

### Adding New Benchmarks

To contribute benchmark data:

1. **Run the test** using methodology above
2. **Record metrics** from API response or UI
3. **Add row to table** with all columns filled
4. **Include notes** about any special configuration

Example benchmark data format:

```
Model: qwen2.5:0.5b
Mode: CPU
Prompt: "Tell me a short story"
Response token/s: 2.44
Prompt token/s: 211.73
Total duration: 167982550221 ns (2m 47s)
Prompt eval count: 34
Eval count: 408
```

Convert to table row:

```
| qwen2.5:0.5b | CPU | 2.44 | 211.73 | 2m 47s | 34 | 408 | Baseline CPU performance |
```

---

## Additional Resources

- [NVIDIA Container Toolkit Documentation](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- [Docker GPU Support](https://docs.docker.com/config/containers/resource_constraints/#gpu)
- [NVIDIA Driver Downloads](https://www.nvidia.com/download/index.aspx)
- [Ubuntu NVIDIA Driver Installation](https://ubuntu.com/server/docs/nvidia-drivers-installation)

---

## Maintenance

### Updating Drivers

```bash
# Check for updates
sudo apt-get update
sudo apt-get upgrade nvidia-driver-570

# Reboot after driver updates
sudo reboot
```

### Updating Container Toolkit

```bash
sudo apt-get update
sudo apt-get upgrade nvidia-container-toolkit

# Restart Docker after toolkit updates
sudo systemctl restart docker
```

---

**Last Updated:** January 26, 2026  
**Tested On:** Ubuntu 24.04 LTS with NVIDIA RTX 2000 Ada Generation  
**Status:** Production Ready ✅
