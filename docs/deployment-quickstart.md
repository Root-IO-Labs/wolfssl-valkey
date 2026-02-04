# Valkey FIPS Container - Quick Start Deployment Guide

**Image:** valkey-fips-ubuntu:8.1.5
**User:** Non-root (UID 1001)
**Base:** Ubuntu 22.04 LTS with wolfSSL FIPS v5

---

## Prerequisites

- Docker Engine 20.10+ with BuildKit
- Host running Linux kernel >= 6.8.x (for FIPS OE compliance)
- x86_64 architecture with RDRAND support (recommended)

---

## Quick Start

### 1. Prepare Data Directory

The container runs as non-root user (UID 1001) for security. You must set correct permissions on the host volume:

```bash
# Create data directory
sudo mkdir -p /data/valkey

# Set ownership to UID 1001 (container user)
sudo chown -R 1001:1001 /data/valkey

# Set secure permissions
sudo chmod 700 /data/valkey

# Verify permissions
ls -la /data/valkey
# Should show: drwx------ 2 1001 1001
```

### 2. Run Container

```bash
docker run \
  --name valkey-fips \
  --restart=unless-stopped \
  -p 6379:6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -e # Valkey uses numeric databases (0-15), not named databases \
  -v /data/valkey:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

### 3. Verify FIPS Validation

The container performs 6 FIPS validation checks on startup:

```bash
docker logs valkey-fips 2>&1 | grep -A 50 "FIPS Validation"
```

**Expected Output:**
```
================================================================================
                          FIPS Validation Starting
================================================================================

[1/6] Validating Operating Environment (OE) for CMVP compliance...
      Detected kernel: 6.8.x
      ✓ Kernel version: 6.8.x (validated range)
      ✓ CPU architecture: x86_64
      ✓ RDRAND: Available (hardware entropy source)

[2/6] Running wolfSSL FIPS startup checks...
      ✓ FIPS mode: Enabled
      ✓ Power-On Self Tests (POST): PASSED
      ✓ Known Answer Tests (KAT): PASSED
      ✓ RNG initialization: PASSED

[3/6] Verifying OpenSSL configuration...
      ✓ OpenSSL version: 3.0.15
      ✓ wolfProvider loaded and active

[4/6] Validating wolfSSL FIPS module integrity...
      ✓ wolfSSL FIPS v5 module verified

[5/6] Verifying Valkey crypto linkage...
      ✓ Valkey linked to FIPS OpenSSL

[6/6] Verifying no non-FIPS crypto libraries present...
      ✓ No system OpenSSL libraries found

================================================================================
                     ✓ FIPS Validation: PASSED
================================================================================
```

---

## Alternative Deployment Methods

### Method 1: Using Docker Volume (Recommended for Production)

Docker manages volume permissions automatically:

```bash
# Create named volume
docker volume create valkey-fips-data

# Run container
docker run \
  --name valkey-fips \
  --restart=unless-stopped \
  -p 6379:6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -e # Valkey uses numeric databases (0-15), not named databases \
  -v valkey-fips-data:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

### Method 2: Using Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  valkey-fips:
    image: valkey-fips-ubuntu:8.1.5
    container_name: valkey-fips
    restart: unless-stopped
    ports:
      - "6379:6379"
    environment:
      - VALKEY_PASSWORD=secure_password
      - # Valkey uses numeric databases (0-15), not named databases
      - # Valkey uses ACL usernames or default user
    volumes:
      - valkey-fips-data:/bitnami/valkey
    # Optional: Resource limits
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

volumes:
  valkey-fips-data:
    driver: local
```

Start with:
```bash
docker-compose up -d
```

### Method 3: Kubernetes Deployment

See `docs/reference-architecture.md` for complete Kubernetes deployment examples.

---

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `VALKEY_PASSWORD` | Valkey password | `secure_password` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `VALKEY_PORT_NUMBER` | Valkey port | `6379` |
| `VALKEY_DATABASES` | Number of databases | `16` |
| `VALKEY_MAXMEMORY` | Max memory limit | (unlimited) |
| `VALKEY_DISABLE_COMMANDS` | Commands to disable | (none) |
| `VALKEY_AOF_ENABLED` | Enable AOF persistence | `yes` |

### FIPS-Specific

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENSSL_CONF` | OpenSSL config path | `/usr/local/openssl/ssl/openssl.cnf` |
| `OPENSSL_MODULES` | OpenSSL modules path | `/usr/local/lib64/ossl-modules` |
| `LD_LIBRARY_PATH` | Library path | `/usr/local/openssl/lib64:/usr/local/lib` |

---

## Connecting to Valkey

### Using valkey-cli (from host)

```bash
# Install Valkey client if needed
sudo apt-get install valkey-tools

# Connect (with password)
valkey-cli -h localhost -p 6379 -a secure_password

# Or without password (if ALLOW_EMPTY_PASSWORD=yes)
valkey-cli -h localhost -p 6379
```

### Using valkey-cli (from container)

```bash
# With password
docker exec -it valkey-fips valkey-cli -a secure_password

# Without password (if ALLOW_EMPTY_PASSWORD=yes)
docker exec -it valkey-fips valkey-cli
```

### Connection String

```
# Standard Valkey connection
valkey://secure_password@localhost:6379/0

# With TLS (if configured)
valkeys://secure_password@localhost:6379/0
```

---

## Verification Commands

### Check Container Status

```bash
# Container running
docker ps | grep valkey-fips

# View logs
docker logs valkey-fips

# Container resource usage
docker stats valkey-fips
```

### Verify FIPS Mode

```bash
# Check OpenSSL FIPS mode
docker exec valkey-fips openssl list -providers

# Expected output should include:
#   default
#     name: OpenSSL Default Provider
#     version: 3.0.15
#     status: active
#   wolfprovider
#     name: wolfSSL Provider
#     version: 1.1.0
#     status: active
```

### Test Valkey Connection and Operations

```bash
# Simple connection test (PING)
docker exec valkey-fips valkey-cli ping
# Expected: PONG

# Test basic operations
docker exec valkey-fips valkey-cli SET test_key "test_value"
# Expected: OK

docker exec valkey-fips valkey-cli GET test_key
# Expected: test_value

# Get Valkey server info
docker exec valkey-fips valkey-cli INFO server | grep valkey_version
# Expected: valkey_version:8.1.5
```

### Verify Crypto Path (FIPS OpenSSL Linkage)

```bash
# Check Valkey binary linkage to FIPS OpenSSL
docker exec valkey-fips ldd /opt/bitnami/valkey/bin/valkey-server | grep ssl

# Should show FIPS OpenSSL:
#   libssl.so.3 => /usr/local/openssl/lib64/libssl.so.3
#   libcrypto.so.3 => /usr/local/openssl/lib64/libcrypto.so.3
```

---

## Troubleshooting

### Permission Denied Error

**Error:**
```
mkdir: cannot create directory '/bitnami/valkey/data': Permission denied
```

**Solution:**
```bash
sudo chown -R 1001:1001 /data/valkey
sudo chmod 700 /data/valkey
```

### FIPS Validation Failed

**Error:**
```
✗ FIPS VALIDATION FAILED
```

**Check:**
1. Kernel version: `uname -r` (must be >= 6.8.x)
2. CPU architecture: `uname -m` (must be x86_64)
3. Container logs: `docker logs valkey-fips`

### Port Already in Use

**Error:**
```
Error starting userland proxy: listen tcp4 0.0.0.0:6379: bind: address already in use
```

**Solution:**
```bash
# Find process using port 6379
sudo lsof -i :6379

# Stop existing Valkey or use different port
docker run -p 5433:6379 ...
```

### Container Exits Immediately

**Check logs:**
```bash
docker logs valkey-fips
```

**Common causes:**
1. FIPS validation failed (check OE requirements)
2. Invalid environment variables
3. Volume permission issues

---

## Security Considerations

### Non-Root User

The container runs as UID 1001 (non-root) for security:
- Reduced attack surface
- Principle of least privilege
- Compliant with FedRAMP requirements

### Network Security

**Recommended:**
- Use internal Docker network (not host network)
- Enable SSL/TLS for Valkey connections
- Use strong passwords (minimum 16 characters)
- Implement network segmentation

**Example with custom network:**
```bash
# Create network
docker network create --driver bridge valkey-net

# Run container
docker run \
  --name valkey-fips \
  --network valkey-net \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -v /data/valkey:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

### Data at Rest Encryption

Consider using encrypted volumes:

```bash
# Create encrypted volume (example using LUKS)
sudo cryptsetup luksFormat /dev/sdb1
sudo cryptsetup open /dev/sdb1 valkey-encrypted
sudo mkfs.ext4 /dev/mapper/valkey-encrypted
sudo mount /dev/mapper/valkey-encrypted /data/valkey
sudo chown -R 1001:1001 /data/valkey
```

---

## Performance Tuning

### Valkey Configuration

Mount custom `valkey.conf`:

```bash
docker run \
  --name valkey-fips \
  -v /data/valkey:/bitnami/valkey \
  -v /path/to/valkey.conf:/opt/bitnami/valkey/conf/valkey.conf:ro \
  valkey-fips-ubuntu:8.1.5
```

### Resource Limits

```bash
docker run \
  --name valkey-fips \
  --cpus="2" \
  --memory="2g" \
  --memory-swap="2g" \
  -v /data/valkey:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

---

## Backup and Recovery

### Backup

```bash
# Trigger a background save (creates RDB snapshot)
docker exec valkey-fips valkey-cli BGSAVE

# Wait for save to complete
docker exec valkey-fips valkey-cli LASTSAVE

# Copy RDB file from container
docker cp valkey-fips:/bitnami/valkey/data/dump.rdb ./valkey-backup-$(date +%Y%m%d).rdb

# Or copy entire data directory
docker run --rm \
  -v valkey-data:/data \
  -v $(pwd):/backup \
  ubuntu:22.04 \
  tar czf /backup/valkey-backup-$(date +%Y%m%d).tar.gz /data
```

### Restore

```bash
# Stop Valkey container
docker stop valkey-fips

# Restore RDB file to volume
docker cp valkey-backup-20251203.rdb valkey-fips:/bitnami/valkey/data/dump.rdb

# Or restore entire data directory
docker run --rm \
  -v valkey-data:/data \
  -v $(pwd):/backup \
  ubuntu:22.04 \
  tar xzf /backup/valkey-backup-20251203.tar.gz -C /

# Start Valkey container
docker start valkey-fips

# Verify data restored
docker exec valkey-fips valkey-cli DBSIZE
```

### Volume Backup

```bash
# Stop container
docker stop valkey-fips

# Backup volume
sudo tar czf valkey-backup-$(date +%Y%m%d).tar.gz -C /data valkey

# Start container
docker start valkey-fips
```

---

## Next Steps

- Review [Reference Architecture](reference-architecture.md) for production deployments
- See [Verification Guide](verification-guide.md) for compliance testing
- Check [Build Documentation](build-documentation.md) for customization

---

## Support and Issues

For issues or questions:
1. Check container logs: `docker logs valkey-fips`
2. Verify FIPS validation: See section "Verify FIPS Validation" above
3. Review troubleshooting section
4. Consult documentation in `docs/` directory
