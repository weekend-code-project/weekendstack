# SSH Key Configuration

## Overview

SSH keys are stored in `files/ssh/` by default and shared with all Coder workspaces:
- ✅ Directory auto-created on first startup
- ✅ Keys generated in workspaces persist on the host
- ✅ Works out-of-the-box without configuration
- ✅ Easy to use your personal SSH keys instead

## Quick Start

### Fresh Install (No SSH Keys Yet)

1. **Start Coder** (creates `files/ssh/` automatically)
   ```bash
   docker compose --profile dev up -d
   ```

2. **Create workspace and generate SSH keys**
   ```bash
   # Inside workspace terminal
   ssh-keygen -t ed25519 -C "your_email@example.com"
   # Keys saved to ~/.ssh (which is files/ssh/ on host)
   ```

3. **Add public key to GitHub**
   ```bash
   # On host machine (after keys are generated)
   cat files/ssh/id_ed25519.pub
   # Copy and paste to: https://github.com/settings/keys
   ```

### Use Your Existing SSH Keys

**Option 1: Symlink (Recommended)**
```bash
# After first run creates files/ssh/
docker compose --profile dev down
rm -rf files/ssh
ln -s ~/.ssh files/ssh
docker compose --profile dev up -d
```

**Option 2: Environment Variable**
```bash
# In .env (before first run)
SSH_KEY_DIR=/home/yourusername/.ssh
```

**Option 3: Copy Keys After Startup**
```bash
# After stack starts and creates files/ssh/
cp ~/.ssh/id_* files/ssh/
cp ~/.ssh/config files/ssh/ 2>/dev/null || true
```

## How It Works

### Directory Structure
```
weekendstack/
├── files/
│   └── ssh/              # Auto-created by Docker on first run
│       ├── id_ed25519    # Created when you generate keys
│       ├── id_ed25519.pub
│       └── config        # Optional SSH config
```

### Mount Flow
1. **Host**: `files/ssh/` or custom `SSH_KEY_DIR`
2. **Coder container**: `/mnt/host-ssh/` (read-only)
3. **Workspace**: `~/.ssh` → `/mnt/host-ssh` (symlink)

### Benefits
- Directory auto-created - no manual setup needed
- Keys generated in any workspace → saved to `files/ssh/`
- Accessible from host: `cat files/ssh/id_ed25519.pub`
- Shared across all workspaces automatically
- Survives container restarts and rebuilds

## Troubleshooting

### "Read-only file system" warnings
These are harmless. The SSH keys are mounted read-only to prevent accidental modifications.

### SSH keys not working
```bash
# Check if mount exists in Coder container
docker exec coder ls -la /mnt/host-ssh/

# Check in workspace
docker exec <workspace-container> ls -la ~/.ssh/

# Verify symlink
docker exec <workspace-container> readlink ~/.ssh
# Should show: /mnt/host-ssh
```

### Permission denied (publickey)
1. Verify public key is added to GitHub/GitLab
2. Check SSH config exists: `cat ~/.ssh/config`
3. Test SSH connection: `ssh -T git@github.com`

## Advanced: Multiple SSH Keys

If you use different keys for different services:

```bash
# ~/.ssh/config
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github

Host gitlab.com
  HostName gitlab.com
  User git
  IdentityFile ~/.ssh/id_ed25519_gitlab
```

This config file will be automatically mounted and used by workspaces.
