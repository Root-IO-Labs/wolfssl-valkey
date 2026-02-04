# Valkey FIPS Reference Architecture

**Document Version:** 1.0
**Last Updated:** 2025-12-03
**Purpose:** Production Deployment Guidance for FIPS/FedRAMP Environments

---

## 1. Overview

This document provides reference architectures for deploying the Valkey 8.1.5 FIPS-enabled container in production environments requiring FIPS 140-3 compliance and FedRAMP authorization.

### 1.1 Scope

- Production deployment patterns
- Infrastructure requirements
- Network architecture
- High availability configurations
- Disaster recovery
- Security controls
- Monitoring and operations
- Compliance maintenance

### 1.2 Target Audience

- Cloud Architects
- Infrastructure Engineers
- Security Teams
- DevOps/SRE Teams
- Compliance Officers

---

## 2. Core Architecture Principles

### 2.1 FIPS Compliance by Design

All architectures must maintain:

✅ **FIPS Boundary Integrity**
- Container operates within validated OE
- No non-FIPS crypto paths available
- Runtime validation enforced

✅ **Fail-Closed Security**
- Container won't start if FIPS validation fails
- No graceful degradation to non-FIPS mode
- Explicit error reporting

✅ **Audit Trail**
- All FIPS validation logged
- Cryptographic operations traceable
- Compliance evidence retained

---

## 3. Infrastructure Requirements

### 3.1 Host Operating System Requirements

**Mandatory Requirements:**

| Component | Requirement | Verification |
|-----------|-------------|--------------|
| **Kernel** | >= 6.8.x | `uname -r` |
| **Architecture** | x86_64 (amd64) | `uname -m` |
| **CPU Features** | RDRAND (recommended) | `grep rdrand /proc/cpuinfo` |
| **OS** | Ubuntu 22.04/22.04, RHEL 9, or compatible | `lsb_release -a` |

**Compatibility Matrix:**

| Host OS | Kernel | Status | Notes |
|---------|--------|--------|-------|
| Ubuntu 22.04 LTS | 6.8.x+ | ✅ Validated | Recommended |
| Ubuntu 22.04 LTS (HWE) | 6.8.x+ | ✅ Supported | Use HWE kernel |
| RHEL 9.x | 5.14.x+ | ⚠️ Verify | Check wolfSSL CMVP OE |
| Amazon Linux 2023 | 6.1.x+ | ⚠️ Verify | Check kernel version |
| Debian 12 | 6.1.x+ | ⚠️ Verify | May need kernel upgrade |

**Action:** Always verify host kernel against wolfSSL CMVP OE list before deployment.

---

### 3.2 Hardware Requirements

**Minimum Production Configuration:**

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **CPU** | 4 cores | 8 cores | x86_64 with RDRAND |
| **RAM** | 8 GB | 16+ GB | Plus Valkey working set |
| **Storage** | 100 GB SSD | 500+ GB NVMe | For data + WAL |
| **Network** | 1 Gbps | 10 Gbps | Depending on workload |

**Storage Considerations:**
- **Data Volume:** Sized for cache + growth
- **WAL Volume:** 10-20% of data volume
- **Backup Volume:** 2-3x data volume
- **IOPS:** 1000+ for production workloads

---

### 3.3 Container Runtime Requirements

**Supported Runtimes:**

| Runtime | Version | Status | Notes |
|---------|---------|--------|-------|
| **Docker** | 20.10+ | ✅ Validated | BuildKit required for build |
| **containerd** | 1.6+ | ✅ Supported | Via Docker or Kubernetes |
| **Kubernetes** | 1.24+ | ✅ Supported | See Section 5 |
| **Podman** | 4.0+ | ⚠️ Untested | Should work, not validated |

**Required Docker Configuration:**
```yaml
{
  "features": {
    "buildkit": true
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

---

## 4. Deployment Architectures

### 4.1 Architecture 1: Single-Node Development/Testing

**Use Case:** Development, testing, CI/CD pipelines

**Diagram:**
```
┌─────────────────────────────────────┐
│      Host (Ubuntu 22.04)            │
│      Kernel: 6.8.x, x86_64         │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  Valkey FIPS Container    │ │
│  │                               │ │
│  │  - Port: 6379                 │ │
│  │  - Volume: /bitnami/valkey│ │
│  │  - FIPS Validation: ✓         │ │
│  └───────────────────────────────┘ │
│             │                       │
│             ↓                       │
│  /data/valkey (Host Volume)    │
└─────────────────────────────────────┘
```

**Deployment Command:**
```bash
docker run -d \
  --name valkey-fips \
  --restart=unless-stopped \
  -p 6379:6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -e VALKEY_DATABASE_NUM=appdb \
  -v /data/valkey:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

**Characteristics:**
- ✅ Simple deployment
- ✅ Fast startup
- ✅ Development/testing suitable
- ❌ No high availability
- ❌ Not production-ready

**Security Controls:**
- Firewall rules limiting access to 6379
- Strong password enforcement
- Regular backups to separate storage
- FIPS validation on every start

---

### 4.2 Architecture 2: Single-Node Production with Backup

**Use Case:** Small production deployments, single-tenant applications

**Diagram:**
```
┌──────────────────────────────────────────────────────┐
│              Host (Ubuntu 22.04)                     │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      Valkey FIPS Container                 │ │
│  │                                                │ │
│  │  - Primary: 6379                              │ │
│  │  - Metrics: 9187 (valkey_exporter)          │ │
│  │  - Volumes:                                   │ │
│  │    • Data: /data/valkey                   │ │
│  │    • AOF: /data/valkey/appendonly.aof     │ │
│  │    • Backup: /backup/valkey               │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      Backup Container (Cron)                   │ │
│  │  - RDB snapshots scheduled                     │ │
│  │  - AOF persistence enabled                     │ │
│  └────────────────────────────────────────────────┘ │
│                                                      │
│  ┌────────────────────────────────────────────────┐ │
│  │      Monitoring (Optional)                     │ │
│  │  - Prometheus                                  │ │
│  │  - Grafana                                     │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
                         │
                         ↓
              ┌─────────────────────┐
              │  Remote Backup      │
              │  S3 / GCS / Azure   │
              └─────────────────────┘
```

**Docker Compose Example:**
```yaml
version: '3.8'

services:
  valkey:
    image: valkey-fips-ubuntu:8.1.5
    container_name: valkey-fips
    restart: unless-stopped
    ports:
      - "6379:6379"
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
      - VALKEY_DATABASES=16
      - VALKEY_MAXCLIENTS=200
      - VALKEY_AOF_ENABLED=yes
    volumes:
      - valkey_data:/bitnami/valkey
      - valkey_backup:/backup
    healthcheck:
      test: ["CMD", "valkey-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  backup:
    image: valkey:17-alpine
    container_name: valkey-backup
    depends_on:
      - valkey
    environment:
      - VALKEY_PASSWORD=${DB_PASSWORD}
    volumes:
      - valkey_backup:/backup
      - ./scripts/backup.sh:/backup.sh
    command: >
      sh -c "while true; do
        sleep 86400;
        /backup.sh;
      done"

volumes:
  valkey_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /data/valkey
  valkey_backup:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /backup/valkey
```

**Characteristics:**
- ✅ Production-suitable for single-tenant
- ✅ Automated backups
- ✅ Monitoring integration
- ✅ FIPS compliance maintained
- ⚠️ Single point of failure
- ❌ No automatic failover

---

### 4.3 Architecture 3: High Availability with Streaming Replication

**Use Case:** Production applications requiring HA and failover

**Diagram:**
```
┌────────────────────────────────────────────────────────┐
│                Load Balancer / HAProxy                 │
│              (Primary: 6379, Replica: 5433)            │
└─────────────┬────────────────────────┬─────────────────┘
              │                        │
    ┌─────────▼────────┐    ┌─────────▼────────┐
    │  Primary Node    │    │  Replica Node 1  │
    │  Ubuntu 22.04    │    │  Ubuntu 22.04    │
    │  Kernel 6.8.x    │    │  Kernel 6.8.x    │
    │                  │    │                  │
    │  ┌────────────┐  │    │  ┌────────────┐ │
    │  │ Valkey │  │    │  │ Valkey │ │
    │  │ FIPS       │  │◀───┼──│ FIPS       │ │
    │  │ (Primary)  │  │WAL │  │ (Standby)  │ │
    │  └────────────┘  │    │  └────────────┘ │
    │                  │    │                  │
    │  Data: /data/pg  │    │  Data: /data/pg │
    └──────────────────┘    └──────────────────┘
              │
    ┌─────────▼────────┐
    │  Replica Node 2  │
    │  Ubuntu 22.04    │
    │  Kernel 6.8.x    │
    │                  │
    │  ┌────────────┐  │
    │  │ Valkey │  │
    │  │ FIPS       │  │
    │  │ (Standby)  │  │
    │  └────────────┘  │
    │                  │
    │  Data: /data/pg  │
    └──────────────────┘
```

**Configuration Steps:**

**1. Primary Node:**
```bash
# Start primary
docker run -d \
  --name valkey-primary \
  --hostname pg-primary \
  -p 6379:6379 \
  -e VALKEY_REPLICATION_MODE=master \
  -e VALKEY_MASTER_PASSWORD=repl_user \
  -e VALKEY_MASTER_PASSWORD=repl_password \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -v /data/valkey-primary:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5
```

**2. Replica Nodes:**
```bash
# Start replica 1
docker run -d \
  --name valkey-replica-1 \
  --hostname pg-replica-1 \
  -p 5433:6379 \
  -e VALKEY_REPLICATION_MODE=slave \
  -e VALKEY_MASTER_PASSWORD=repl_user \
  -e VALKEY_MASTER_PASSWORD=repl_password \
  -e VALKEY_MASTER_HOST=pg-primary \
  -e VALKEY_MASTER_PORT_NUMBER=6379 \
  -e ALLOW_EMPTY_PASSWORD=yes \
  -v /data/valkey-replica-1:/bitnami/valkey \
  valkey-fips-ubuntu:8.1.5

# Repeat for replica 2 with different port and volume
```

**3. HAProxy Configuration:**
```
global
    log /dev/log local0
    maxconn 4096

defaults
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s

listen valkey-primary
    bind *:6379
    option pgsql-check user valkey
    server primary pg-primary:6379 check

listen valkey-replicas
    bind *:5433
    balance roundrobin
    option pgsql-check user valkey
    server replica1 pg-replica-1:6379 check
    server replica2 pg-replica-2:6379 check
```

**Characteristics:**
- ✅ High availability
- ✅ Read scaling (replicas)
- ✅ Automatic failover (with additional tooling)
- ✅ FIPS compliance on all nodes
- ✅ Production-ready
- ⚠️ Complex setup
- ⚠️ Requires monitoring and automation

---

### 4.4 Architecture 4: Kubernetes Deployment

**Use Case:** Cloud-native, microservices, orchestrated environments

**Diagram:**
```
┌──────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                      │
│                                                           │
│  ┌────────────────────────────────────────────────────┐  │
│  │              Ingress / Load Balancer                │  │
│  └──────────────────┬─────────────────────────────────┘  │
│                     │                                     │
│  ┌──────────────────▼─────────────────────────────────┐  │
│  │              Service (valkey-svc)               │  │
│  │              ClusterIP: 6379                        │  │
│  └──────────────────┬─────────────────────────────────┘  │
│                     │                                     │
│  ┌──────────────────▼─────────────────────────────────┐  │
│  │            StatefulSet (valkey)                 │  │
│  │                                                     │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │  │
│  │  │   Pod 0     │  │   Pod 1     │  │   Pod 2    │ │  │
│  │  │  (Primary)  │  │  (Replica)  │  │  (Replica) │ │  │
│  │  │             │  │             │  │            │ │  │
│  │  │  PG FIPS    │  │  PG FIPS    │  │  PG FIPS   │ │  │
│  │  │             │  │             │  │            │ │  │
│  │  │  PVC: 100Gi │  │  PVC: 100Gi │  │  PVC:100Gi │ │  │
│  │  └─────────────┘  └─────────────┘  └────────────┘ │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  Nodes: Ubuntu 22.04, Kernel 6.8.x, x86_64              │
└──────────────────────────────────────────────────────────┘
```

**Kubernetes Manifests:**

**1. Namespace:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: valkey-fips
  labels:
    fips: "enabled"
    compliance: "fedramp"
```

**2. Secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: valkey-secret
  namespace: valkey-fips
type: Opaque
stringData:
  valkey-password: "SecurePassword123!"
  replication-password: "ReplPassword123!"
```

**3. ConfigMap:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: valkey-config
  namespace: valkey-fips
data:
  valkey.conf: |
    # FIPS-compliant Valkey configuration
    max_connections = 200
    shared_buffers = 2GB
    effective_cache_size = 6GB
    maintenance_work_mem = 512MB
    checkpoint_completion_target = 0.9
    wal_buffers = 16MB
    default_statistics_target = 100
    random_page_cost = 1.1
    effective_io_concurrency = 200
    work_mem = 10MB
    min_wal_size = 1GB
    max_wal_size = 4GB

    # SSL/TLS (FIPS-enabled)
    ssl = on
    ssl_ciphers = 'HIGH:!aNULL:!MD5'
    ssl_prefer_server_ciphers = on

    # Logging
    log_destination = 'stderr'
    logging_collector = on
    log_directory = '/opt/bitnami/valkey/logs'
    log_filename = 'valkey-%Y-%m-%d.log'
    log_rotation_age = 1d
    log_rotation_size = 100MB
    log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
    log_timezone = 'UTC'
```

**4. StatefulSet:**
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: valkey
  namespace: valkey-fips
spec:
  serviceName: valkey-headless
  replicas: 3
  selector:
    matchLabels:
      app: valkey
      fips: enabled
  template:
    metadata:
      labels:
        app: valkey
        fips: enabled
    spec:
      # Node selection for FIPS-compatible hosts
      nodeSelector:
        kubernetes.io/arch: amd64
        kernel-version: "6.8"

      # Security context
      securityContext:
        fsGroup: 1001
        runAsUser: 1001
        runAsNonRoot: true

      containers:
      - name: valkey
        image: valkey-fips-ubuntu:8.1.5
        imagePullPolicy: IfNotPresent

        ports:
        - name: valkey
          containerPort: 6379

        env:
        - name: VALKEY_PASSWORD
          valueFrom:
            secretKeyRef:
              name: valkey-secret
              key: valkey-password
        - name: VALKEY_DATABASE_NUM
          value: "production_db"
        - name: VALKEY_REPLICATION_MODE
          value: "master"  # Set to "slave" for replicas
        - name: VALKEY_MASTER_PASSWORD
          value: "repl_user"
        - name: VALKEY_MASTER_PASSWORD
          valueFrom:
            secretKeyRef:
              name: valkey-secret
              key: replication-password

        volumeMounts:
        - name: data
          mountPath: /bitnami/valkey
        - name: config
          mountPath: /opt/bitnami/valkey/conf/valkey.conf
          subPath: valkey.conf

        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - valkey-cli ping
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - valkey-cli ping
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "8Gi"
            cpu: "4000m"

      volumes:
      - name: config
        configMap:
          name: valkey-config

  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "fast-ssd"
      resources:
        requests:
          storage: 100Gi
```

**5. Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: valkey
  namespace: valkey-fips
spec:
  type: ClusterIP
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
    name: valkey
  selector:
    app: valkey
---
apiVersion: v1
kind: Service
metadata:
  name: valkey-headless
  namespace: valkey-fips
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - port: 6379
    targetPort: 6379
    protocol: TCP
    name: valkey
  selector:
    app: valkey
```

**6. NetworkPolicy (Optional, for strict isolation):**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: valkey-netpol
  namespace: valkey-fips
spec:
  podSelector:
    matchLabels:
      app: valkey
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          authorized: "true"
    ports:
    - protocol: TCP
      port: 6379
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 53  # DNS
```

**Deployment Commands:**
```bash
# Create namespace and resources
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f configmap.yaml
kubectl apply -f statefulset.yaml
kubectl apply -f service.yaml

# Verify deployment
kubectl get pods -n valkey-fips
kubectl logs -n valkey-fips valkey-0 | grep "FIPS VALIDATION"

# Test connection
kubectl run -it --rm valkey-client --image=valkey:7-alpine --namespace=valkey-fips -- \
  valkey-cli -h valkey.valkey-fips.svc.cluster.local ping
```

**Characteristics:**
- ✅ Cloud-native deployment
- ✅ Automatic pod rescheduling
- ✅ Persistent storage
- ✅ Service discovery
- ✅ FIPS compliance per pod
- ✅ Horizontal scalability (read replicas)
- ✅ Production-grade
- ⚠️ Requires Kubernetes expertise
- ⚠️ Node selector ensures FIPS-compatible hosts

---

## 5. Network Architecture

### 5.1 Network Security Zones

**Recommended Zone Segmentation:**

```
┌─────────────────────────────────────────────────┐
│         Internet / Public Zone                  │
└──────────────────┬──────────────────────────────┘
                   │
         ┌─────────▼─────────┐
         │   Load Balancer   │
         │   (TLS Termination│
         │    with FIPS)     │
         └─────────┬─────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│         DMZ / Application Zone                  │
│  ┌───────────────────────────────────────────┐  │
│  │     Application Servers                   │  │
│  │     (Can connect to Valkey)           │  │
│  └───────────────────────────────────────────┘  │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│         Database Zone (Restricted)              │
│  ┌───────────────────────────────────────────┐  │
│  │     Valkey FIPS Cluster               │  │
│  │     (6379 - No external access)           │  │
│  └───────────────────────────────────────────┘  │
│                                                  │
│  Access:                                         │
│  - Application Zone: ✓ Allowed                  │
│  - DMZ: ✗ Blocked                                │
│  - Internet: ✗ Blocked                           │
└──────────────────────────────────────────────────┘
```

### 5.2 Firewall Rules

**Database Zone Ingress Rules:**
```bash
# Allow Valkey from application zone
iptables -A INPUT -p tcp --dport 6379 -s 10.0.2.0/24 -j ACCEPT

# Allow replication between Valkey nodes
iptables -A INPUT -p tcp --dport 6379 -s 10.0.3.0/24 -j ACCEPT

# Block all other access
iptables -A INPUT -p tcp --dport 6379 -j DROP
```

### 5.3 TLS/SSL Configuration

**Client Connection Security:**

All client connections should use SSL/TLS:

```bash
# Client connection string
valkey://user:pass@host:6379/db?sslmode=require&sslrootcert=/path/to/ca.crt
```

**SSL Mode Options:**
- `require` - Minimum for production
- `verify-ca` - Verify server certificate
- `verify-full` - Verify server certificate and hostname

**FIPS-Approved Cipher Suites:**
```
TLS_AES_256_GCM_SHA384
TLS_AES_128_GCM_SHA256
TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
```

---

## 6. Data Management

### 6.1 Storage Configuration

**Production Storage Layout:**

```
/data/
├── valkey/          # Valkey data directory
│   ├── data/           # Database files
│   ├── appendonly.aof  # AOF persistence file
│   └── dump.rdb        # RDB snapshot file
├── backup/              # Local backup staging
│   ├── snapshots/      # RDB snapshots
│   ├── aof/            # AOF backups
│   └── exports/        # Exported backups
└── logs/                # Application logs
    ├── valkey/          # Valkey logs
    └── fips/           # FIPS validation logs
```

**Storage Classes:**
- **Data:** High-performance SSD/NVMe (lowest latency for RDB/AOF writes)
- **Backup:** Standard SSD or HDD (cost-effective, sequential writes)
- **Logs:** Standard SSD

### 6.2 Backup Strategy

**3-2-1 Backup Rule:**
- **3** copies of data
- **2** different storage types
- **1** off-site copy

**Backup Types:**

1. **Continuous WAL Archiving**
   ```bash
   # Enable WAL archiving
   archive_mode = on
   archive_command = 'cp %p /backup/wal_archive/%f'
   ```

2. **Base Backups (Daily)**
   ```bash
   # valkey-cli BGSAVE
   docker exec valkey-fips valkey-cli BGSAVE
   # Wait for save to complete
   docker exec valkey-fips valkey-cli LASTSAVE
   # Copy RDB snapshot
   docker cp valkey-fips:/bitnami/valkey/data/dump.rdb \
     /backup/snapshots/dump_$(date +%Y%m%d).rdb
   ```

3. **AOF Backups (Continuous)**
   ```bash
   # AOF provides continuous backup - copy AOF file
   docker exec valkey-fips valkey-cli BGREWRITEAOF
   # Copy AOF file when rewrite completes
   docker cp valkey-fips:/bitnami/valkey/data/appendonly.aof \
     /backup/aof/appendonly_$(date +%Y%m%d).aof
   ```

**Backup Schedule:**
- Continuous: AOF persistence (every write)
- Daily: RDB snapshot (retain 7 days)
- Weekly: RDB snapshot (retain 4 weeks)
- Monthly: RDB snapshot (retain 12 months)

**Off-site Backup:**
```bash
# Sync to S3 (FIPS-compliant endpoint)
aws s3 sync /backup/base/ \
  s3://backups/valkey-fips/base/ \
  --sse AES256
```

### 6.3 Disaster Recovery

**Recovery Time Objective (RTO):** < 4 hours
**Recovery Point Objective (RPO):** < 15 minutes

**Recovery Procedures:**

1. **Point-in-Time Recovery (PITR)**
   ```bash
   # Restore base backup
   tar -xzf /backup/base/20251203.tar.gz -C /data/valkey/

   # Configure recovery
   cat > /data/valkey/recovery.conf <<EOF
   restore_command = 'cp /backup/wal_archive/%f %p'
   recovery_target_time = '2025-12-03 14:30:00'
   EOF

   # Start Valkey
   docker start valkey-fips
   ```

2. **Standby Promotion (HA Failover)**
   ```bash
   # Promote replica to primary
   docker exec valkey-replica-1 \
     valkey-cli REPLICAOF NO ONE -D /bitnami/valkey/data
   ```

---

## 7. Monitoring and Observability

### 7.1 Metrics to Monitor

**FIPS Compliance Metrics:**
- Container startup success rate
- FIPS validation pass/fail rate
- Non-FIPS library detection events
- Entropy availability

**Valkey Metrics:**
- Connection count
- Transaction rate (commits/rollbacks)
- Query latency (p50, p95, p99)
- Cache hit ratio
- Replication lag (HA setups)
- Disk I/O and space usage

**System Metrics:**
- CPU utilization
- Memory usage
- Disk I/O (IOPS, throughput)
- Network I/O

### 7.2 Prometheus Monitoring

**valkey_exporter Configuration:**
```yaml
# docker-compose.yml addition
  valkey-exporter:
    image: quay.io/prometheuscommunity/valkey-exporter:latest
    ports:
      - "9187:9187"
    environment:
      - DATA_SOURCE_NAME=valkey://valkey:password@valkey:6379/valkey?sslmode=require
    depends_on:
      - valkey
```

**Key Prometheus Queries:**
```promql
# Connection count
valkey__numbackends{datname="production_db"}

# Transaction rate
rate(valkey__xact_commit{datname="production_db"}[5m])

# Cache hit ratio
rate(valkey__blks_hit[5m]) /
(rate(valkey__blks_hit[5m]) + rate(valkey__blks_read[5m]))

# Replication lag
valkey_master_repl_offset
```

### 7.3 Logging

**Log Aggregation:**
- Centralized logging via ELK, Splunk, or CloudWatch
- FIPS validation logs retained for audit
- Valkey query logs (configurable verbosity)

**Log Retention:**
- Operational logs: 30 days
- Security/audit logs: 1 year minimum (FedRAMP requirement)
- FIPS validation logs: Permanent

---

## 8. Security Controls

### 8.1 Access Control

**Database Users:**
- **Superuser (valkey):** Break-glass only, MFA required
- **Application Users:** Least privilege, connection limits
- **Replication User:** Replication-only privileges
- **Monitoring User:** Read-only statistics access

**Example User Creation:**
```bash
# Application user with full access
valkey-cli ACL SETUSER app_user on >secure_password ~* +@all

# Read-only monitoring user
valkey-cli ACL SETUSER monitor on >monitor_password ~* +@read +info +ping

# List all users
valkey-cli ACL LIST
```

### 8.2 Network Isolation

**Container Network:**
```bash
# Create isolated network
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --opt com.docker.network.bridge.name=br-pg-fips \
  valkey-fips-net

# Run container on isolated network
docker run -d \
  --network valkey-fips-net \
  --name valkey-fips \
  valkey-fips-ubuntu:8.1.5
```

### 8.3 Secrets Management

**Recommended Solutions:**
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- Kubernetes Secrets (with encryption at rest)

**Example with Vault:**
```bash
# Store secret in Vault
vault kv put secret/valkey/production \
  password="SecurePassword123!"

# Retrieve in container
export ALLOW_EMPTY_PASSWORD=yes kv get -field=password secret/valkey/production)
```

---

## 9. Operational Procedures

### 9.1 Deployment Checklist

**Pre-Deployment:**
- [ ] Host kernel >= 6.8.x verified
- [ ] Host architecture is x86_64
- [ ] RDRAND available (check /proc/cpuinfo)
- [ ] Storage provisioned and mounted
- [ ] Network configuration completed
- [ ] Secrets configured
- [ ] Backup solution in place
- [ ] Monitoring configured

**During Deployment:**
- [ ] Container starts successfully
- [ ] FIPS validation passes (check logs)
- [ ] Database initializes
- [ ] Connectivity test passes
- [ ] SSL/TLS enabled and working
- [ ] Replication configured (if HA)

**Post-Deployment:**
- [ ] Backup test successful
- [ ] Monitoring dashboards show data
- [ ] Alerting rules configured
- [ ] Documentation updated
- [ ] Runbook created

### 9.2 Upgrade Procedures

**Rolling Upgrade (Zero Downtime):**

1. **Upgrade replica 1:**
   ```bash
   docker stop valkey-replica-1
   docker rm valkey-replica-1
   docker run -d --name valkey-replica-1 \
     [same config with new image version]
   # Wait for catch-up
   ```

2. **Upgrade replica 2:**
   (Repeat step 1)

3. **Failover to replica:**
   ```bash
   # Promote replica-1 to primary
   docker exec valkey-replica-1 valkey-cli REPLICAOF NO ONE
   ```

4. **Upgrade old primary:**
   ```bash
   docker stop valkey-primary
   # Reconfigure as replica with new image
   ```

5. **Failover back (optional)**

### 9.3 Incident Response

**FIPS Validation Failure:**
1. Container won't start, logs show FIPS failure
2. Check:
   - Host kernel version
   - CPU architecture
   - Entropy availability
   - System OpenSSL presence (should be absent)
3. Review `docs/verification-guide.md` for troubleshooting
4. Escalate to security team if crypto module compromised

**Performance Degradation:**
1. Check monitoring dashboards
2. Investigate slow commands (valkey-cli SLOWLOG GET)
3. Review connection count (valkey-cli INFO clients)
4. Check memory usage and disk I/O
5. Scale horizontally (add read replicas) if needed

---

## 10. Compliance Maintenance

### 10.1 Continuous Compliance

**Monthly Tasks:**
- Review FIPS validation logs
- Update security patches
- Test backups and recovery
- Review access logs

**Quarterly Tasks:**
- Full disaster recovery test
- Security assessment
- Compliance documentation review
- Update OE mapping if kernel changes

**Annually:**
- Re-run full verification suite
- Update wolfSSL CMVP certificate (if renewed)
- Compliance audit preparation
- Training for operations team

### 10.2 Audit Readiness

**Evidence Collection:**
- FIPS validation logs (daily)
- Backup success logs
- Access audit logs
- Change management records
- Incident response records

**3PAO Review Package:**
- Architecture diagrams (this document)
- Network diagrams
- Data flow diagrams
- Security controls documentation
- Verification test results
- CMVP certificate and OE mapping

---

## 11. Cost Optimization

### 11.1 Resource Right-Sizing

**Development/Test:**
- Smaller instances (2 CPU, 4 GB RAM)
- Standard SSD storage
- No high availability

**Production:**
- Right-sized based on workload profiling
- Use auto-scaling for read replicas
- Reserved/committed use discounts

### 11.2 Storage Optimization

- Compress backups
- Use lifecycle policies (move to cold storage after 90 days)
- Vacuum and analyze cache regularly
- Archive old data to cheaper storage

---

## 12. Migration Strategies

### 12.1 Migrating from Non-FIPS Valkey

**Approach:** Blue-Green Deployment

1. **Prepare:** Set up FIPS environment (green)
2. **Sync:** Replicate from existing (blue) to new (green)
3. **Test:** Validate FIPS environment works
4. **Switch:** Update DNS/load balancer to green
5. **Monitor:** Watch for issues
6. **Decommission:** Shut down blue after stability period

**Valkey Replication:**
```bash
# On existing (blue) Valkey - ensure it's configured as master
# No special configuration needed - master accepts replica connections by default

# On FIPS (green) Valkey - configure as replica
docker exec green-valkey valkey-cli REPLICAOF blue-db 6379

# Verify replication status
docker exec green-valkey valkey-cli INFO replication

# To promote replica to master later
docker exec green-valkey valkey-cli REPLICAOF NO ONE
```

---

## Appendices

### Appendix A: Quick Reference

**Environment Variables:**
```bash
VALKEY_PASSWORD        # Admin password
VALKEY_DATABASE_NUM        # Initial cache
VALKEY_ACL_USERNAME        # Custom admin user
VALKEY_MAXCLIENTS # Max connections (default: 100)
VALKEY_REPLICATION_MODE # master/slave
OPENSSL_CONF               # OpenSSL config (set by image)
```

### Appendix B: Useful Commands

```bash
# Check FIPS validation
docker logs <container> | grep "FIPS VALIDATION"

# Connect to cache
docker exec -it <container> valkey-cli

# View replication status
docker exec <container> valkey-cli INFO replication | grep connected_slaves

# Check Valkey version
docker exec <container> valkey-server --version

# Backup cache (creates dump.rdb)
docker exec <container> valkey-cli BGSAVE
docker cp <container>:/data/dump.rdb backup.rdb

# Restore cache
docker cp backup.rdb <container>:/data/dump.rdb
docker restart <container>
```

---

**Document Status:** Complete - Ready for Production Deployment

**Version History:**
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-12-03 | Initial reference architecture |

**Next Review:** Upon major version update or infrastructure change

**Owner:** Root FIPS Implementation Team

**Classification:** Internal - Architecture Guide
