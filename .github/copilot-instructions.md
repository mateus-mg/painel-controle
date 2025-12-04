````instructions
# Copilot Instructions - Painel de Controle

## Project Overview
Bash script for managing external HD and Docker containers in a home server. Handles mounting/unmounting of HD and Docker operations with temporary keepalive mode. Located in `painel-controle/`.

## Architecture

**Main Script:** `painel-controle/painel.sh` (~450 lines)
- Single bash script with modular functions
- No external dependencies beyond standard Unix tools (mountpoint, grep, sed, docker)
- Auto-discovers services from docker-compose.yml
- Temporary keepalive system until NAS acquisition

**Key Components:**
- `is_hd_mounted()`: Validates HD mount status (mountpoint + /proc/mounts fallback)
- `mount_hd_simple()`: Mounts HD with permission handling
- `unmount_hd_forced()`: Stops Docker, syncs, unmounts (safe shutdown)
- `keepalive_hd_optimized()`: Monitors HD/containers every 30s, auto-remounts
- `get_docker_services()`: Auto-discovers services from docker-compose.yml

## Critical Patterns

**HD Configuration (Lines 7-13):**
```bash
HD_MOUNT_POINT="/media/mateus/Servidor"
HD_UUID="35feb867-8ee2-49a9-a1a5-719a67e3975a"
HD_LABEL="Servidor"
HD_DEVICE="/dev/sdb1"
HD_TYPE="ext4"
DOCKER_COMPOSE_DIR="/home/mateus"
```

**Mount Verification (Lines 145-155):**
```bash
is_hd_mounted() {
    if mountpoint -q "$HD_MOUNT_POINT" 2>/dev/null; then
        return 0
    fi
    if grep -qs "$HD_MOUNT_POINT" /proc/mounts; then
        return 0
    fi
    return 1
}
```

**Service Auto-Discovery (Lines 25-40):**
```bash
# Uses docker compose config --services
# Fallback: grep '^  [a-zA-Z0-9_-]+:' from YAML
get_docker_services() {
    cd "$DOCKER_COMPOSE_DIR" && docker compose config --services 2>/dev/null
}
```

**Keepalive Loop (Lines 235-270):**
```bash
# 30-second interval monitoring
# Remounts HD on disconnect
# Restarts stopped containers
# Uses touch to keep HD active
```

## Developer Workflows

**Install globally:**
```bash
sudo cp painel.sh /usr/local/bin/painel
sudo chmod +x /usr/local/bin/painel
painel status
```

**Typical startup:**
```bash
painel mount           # Mount HD
painel start           # Start all containers
painel keepalive       # Activate monitoring (Ctrl+C to stop)
```

**Service-specific operations:**
```bash
painel start jellyfin      # Start only Jellyfin
painel restart qbittorrent # Restart qBittorrent
painel logs prowlarr -f    # Follow Prowlarr logs
```

## Command Reference

**HD Management:**
- `painel mount` - Mounts external HD
- `painel unmount` - Stops Docker, unmounts HD safely
- `painel check` - Shows active mounts
- `painel fix` - Recreates mount point with correct permissions
- `painel force-mount` - Force complete remount sequence

**Docker Operations:**
- `painel start [service]` - Start all or specific container
- `painel stop [service]` - Stop all or specific container
- `painel restart [service]` - Restart all or specific container
- `painel ps` - List running containers
- `painel logs <service>` - View service logs
- `painel services` - List available services

**Monitoring:**
- `painel status` - Complete system status
- `painel keepalive` - Continuous monitoring mode
- `painel diagnose` - Full diagnostic report

## Key Conventions

1. **Always verify mount before Docker operations**: Prevents data corruption
2. **Stop Docker before unmounting**: Ensures clean shutdown
3. **Use sudo only when necessary**: mount/umount operations only
4. **Service names match docker-compose.yml**: Auto-discovered, no hardcoding
5. **Logging pattern**: Timestamps in ISO format to `~/.painel.log`
6. **Return codes**: 0=success, 1=error (consistent across functions)

## Integration Points

**External dependencies:**
- Docker Compose v2: Service management (required)
- mountpoint: Mount verification (required)
- lsof: Process checking (optional, for safety)
- findmnt/lsblk: Diagnostics (optional)

**File system:**
- HD mounts at `/media/mateus/Servidor`
- Docker compose at `/home/mateus/docker-compose.yml`
- Logs at `~/.painel.log`

## Common Issues

**HD won't mount:** Check device exists (`lsblk`), fix mount point (`painel fix`), force mount (`painel force-mount`)

**Containers won't start:** Verify HD is mounted first, check docker-compose.yml exists, review logs

**Keepalive fails:** Check HD connection, review `~/.painel.log`, verify Docker status

## Critical Safety Patterns

**Pre-unmount validation:**
```bash
# MUST stop Docker before unmounting
stop_docker_services
sleep 3  # Allow containers to release files
sync     # Flush filesystem buffers
```

**Mount point creation:**
```bash
# MUST set correct ownership
sudo mkdir -p "$HD_MOUNT_POINT"
sudo chown mateus:mateus "$HD_MOUNT_POINT"
sudo chmod 755 "$HD_MOUNT_POINT"
```

**Docker startup validation:**
```bash
# MUST verify HD mounted before starting
if ! is_hd_mounted; then
    echo "❌ HD not mounted. Mount first: painel mount"
    return 1
fi
```

## Keepalive Behavior

**Purpose:** Temporary solution until NAS acquisition - keeps HD active and monitors containers

**Operation:**
- Checks HD mount every 30 seconds
- Auto-remounts on disconnect
- Restarts stopped containers
- Maintains HD activity with touch

**Optimization tips:**
- Use 60s interval for lighter load
- Replace `touch` with `dd` read for less wear
- Touch only every 10 minutes (300s)
- Don't verify containers constantly (Docker manages)

**Exit:** Press Ctrl+C (should implement trap for clean exit)

## Known Limitations

1. **Race condition in grep:** `grep -q "$service"` matches partial names (e.g., "jellyfin" matches "jellyfin-backup")
   - **Fix:** Use `grep -qx` for exact match or `docker compose ps`

2. **Infinite retry loop:** No backoff on repeated failures
   - **Fix:** Add retry counter with 5-min pause after 3 failures

3. **No signal handling:** Ctrl+C may leave inconsistent state
   - **Fix:** Add `trap cleanup_on_exit SIGINT SIGTERM`

4. **Unsafe unmount:** Doesn't check for open files
   - **Fix:** Use `lsof` to verify no processes using HD

5. **Aggressive touch:** Writes to disk every 30s
   - **Fix:** Read-only check or touch every 10 minutes

6. **No log rotation:** `~/.painel.log` grows indefinitely
   - **Fix:** Tail last 500 lines on rotation

## Best Practices

**When editing:**
1. Test mount/unmount before Docker operations
2. Always validate return codes
3. Use absolute paths (no relative paths)
4. Quote variables: `"$var"` not `$var`
5. Prefer `[[ ]]` over `[ ]` for conditionals
6. Use `local` for function variables

**Error handling:**
```bash
# GOOD: Check return and provide context
if ! mount_hd_simple; then
    echo "❌ Failed to mount HD"
    return 1
fi

# BAD: Silent failure
mount_hd_simple
```

**Service validation:**
```bash
# GOOD: Validate service exists
if [[ " ${DOCKER_SERVICES[@]} " =~ " $service " ]]; then
    docker compose restart "$service"
fi

# BAD: No validation
docker compose restart "$2"
```

## Troubleshooting Commands

```bash
# Check HD status
lsblk | grep sdb
sudo blkid | grep Servidor
mountpoint /media/mateus/Servidor

# Check mounts
findmnt | grep sdb
cat /proc/mounts | grep Servidor

# Check Docker
cd /home/mateus && docker compose config --services
docker ps -a

# Check processes using HD
lsof /media/mateus/Servidor

# View logs
tail -f ~/.painel.log
```

## Future Improvements (Post-NAS)

- [ ] Remove keepalive (not needed with NAS)
- [ ] Simplify mounting (permanent mount in fstab)
- [ ] Add automatic backups
- [ ] Integrate systemd for auto-start
- [ ] Add web interface (optional)
- [ ] Notification system (desktop/mobile)

````