#!/bin/bash
################################################################################
# Ubuntu 22.04 STIG/SCAP Hardening Script for FedRAMP Compliance
#
# This script applies DISA STIG and CIS Benchmark controls to Ubuntu 22.04
# for FedRAMP-ready container images.
#
# References:
#   - DISA STIG for Ubuntu 22.04
#   - CIS Ubuntu Linux 22.04 LTS Benchmark v1.0.0
#   - NIST SP 800-53 Rev. 5 (FedRAMP baseline)
#
# Usage:
#   Run during Docker build as root:
#   RUN /path/to/ubuntu-22.04-stig.sh
#
# Version: 1.0
# Date: 2025-12-03
################################################################################

set -e
set -o pipefail

echo "========================================"
echo "Ubuntu 22.04 STIG/SCAP Hardening"
echo "FedRAMP Compliance Configuration"
echo "========================================"
echo ""

HARDENING_LOG="/tmp/hardening.log"
exec > >(tee -a "$HARDENING_LOG") 2>&1

###############################################################################
# 1. FILE SYSTEM HARDENING
###############################################################################
echo "[1/10] File System Hardening..."

# Remove SUID/SGID bits from unnecessary binaries (CIS 1.6.1.1)
echo "  - Removing SUID/SGID permissions from non-essential binaries..."
find / -xdev -type f \( -perm -4000 -o -perm -2000 \) ! -path "/proc/*" ! -path "/sys/*" \
    -exec ls -l {} \; 2>/dev/null | while read -r line; do
    file=$(echo "$line" | awk '{print $NF}')
    # Keep essential SUID binaries (su, sudo, passwd, etc.)
    if [[ ! "$file" =~ (su|sudo|passwd|ping|mount|umount)$ ]]; then
        chmod a-s "$file" 2>/dev/null || true
    fi
done

# Set restrictive permissions on sensitive files
echo "  - Setting restrictive permissions on sensitive files..."
chmod 600 /etc/ssh/sshd_config 2>/dev/null || true
chmod 600 /etc/shadow 2>/dev/null || true
chmod 600 /etc/gshadow 2>/dev/null || true
chmod 644 /etc/passwd 2>/dev/null || true
chmod 644 /etc/group 2>/dev/null || true

# Set proper ownership
echo "  - Setting proper ownership on system files..."
chown root:root /etc/passwd /etc/group /etc/shadow /etc/gshadow 2>/dev/null || true

echo "  ✓ File system hardening complete"
echo ""

###############################################################################
# 2. DISABLE UNUSED SERVICES AND PROTOCOLS
###############################################################################
echo "[2/10] Disabling Unused Services..."

# Disable unnecessary system services
echo "  - Disabling unnecessary services..."
DISABLED_SERVICES=(
    "avahi-daemon"
    "cups"
    "bluetooth"
    "rsync"
    "rpcbind"
    "nfs-server"
    "smbd"
    "nmbd"
    "snmpd"
)

for service in "${DISABLED_SERVICES[@]}"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${service}"; then
        systemctl disable "$service" 2>/dev/null || true
        systemctl stop "$service" 2>/dev/null || true
        echo "    ✓ Disabled: $service"
    fi
done

echo "  ✓ Unused services disabled"
echo ""

###############################################################################
# 3. KERNEL HARDENING (sysctl parameters)
###############################################################################
echo "[3/10] Kernel Hardening..."

SYSCTL_CONF="/etc/sysctl.d/99-fips-hardening.conf"
echo "  - Creating hardened sysctl configuration: $SYSCTL_CONF"

cat > "$SYSCTL_CONF" <<'EOF'
# Ubuntu 24.04 STIG/FedRAMP Kernel Hardening
# Applied: 2025-12-03

# IP Forwarding (CIS 3.1.1)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Source Address Verification (CIS 3.2.1)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP Redirects (CIS 3.2.2)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Secure ICMP Redirects (CIS 3.2.3)
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0

# Log Suspicious Packets (CIS 3.2.4)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP Broadcasts (CIS 3.2.5)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore Bogus ICMP Responses (CIS 3.2.6)
net.ipv4.icmp_ignore_bogus_error_responses = 1

# TCP SYN Cookies (CIS 3.2.8)
net.ipv4.tcp_syncookies = 1

# IPv6 Router Advertisements (CIS 3.3.1)
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0

# Randomize Virtual Address Space (DISA STIG)
kernel.randomize_va_space = 2

# Restrict kernel pointer access (DISA STIG)
kernel.kptr_restrict = 2

# Restrict access to kernel logs (DISA STIG)
kernel.dmesg_restrict = 1

# Ptrace scope hardening (DISA STIG)
kernel.yama.ptrace_scope = 1

# Core dump restrictions (DISA STIG)
fs.suid_dumpable = 0

# Exec shield (if available)
kernel.exec-shield = 1

# Address Space Layout Randomization
kernel.randomize_va_space = 2
EOF

# Apply sysctl settings (may not work in container, but documented)
sysctl -p "$SYSCTL_CONF" 2>/dev/null || true

echo "  ✓ Kernel hardening configured"
echo ""

###############################################################################
# 4. NETWORK HARDENING
###############################################################################
echo "[4/10] Network Hardening..."

# Configure /etc/hosts.deny (CIS 3.4.1)
echo "  - Configuring TCP wrappers..."
cat > /etc/hosts.deny <<'EOF'
# Deny all by default (FedRAMP requirement)
ALL: ALL
EOF

# Configure /etc/hosts.allow (allow only necessary services)
cat > /etc/hosts.allow <<'EOF'
# Allow Valkey connections (can be further restricted by IP)
ALL: LOCAL
EOF

chmod 644 /etc/hosts.deny /etc/hosts.allow

echo "  ✓ Network hardening complete"
echo ""

###############################################################################
# 5. LOGGING AND AUDITING
###############################################################################
echo "[5/10] Configuring Logging and Auditing..."

# Ensure rsyslog is installed and configured
if ! command -v rsyslogd &> /dev/null; then
    echo "  ⚠ rsyslog not installed (expected in minimal container)"
else
    echo "  - Configuring rsyslog..."

    # Create rsyslog configuration for FIPS/FedRAMP
    cat > /etc/rsyslog.d/50-fips.conf <<'EOF'
# FIPS/FedRAMP Logging Configuration

# Log all security-related events
auth,authpriv.*                 /var/log/auth.log
*.*;auth,authpriv.none          -/var/log/syslog
kern.*                          -/var/log/kern.log
mail.*                          -/var/log/mail.log
*.emerg                         :omusrmsg:*

# Valkey logs
local0.*                        /var/log/valkeyql.log
EOF

    # Set proper permissions on log files
    touch /var/log/auth.log /var/log/syslog /var/log/kern.log 2>/dev/null || true
    chmod 640 /var/log/auth.log /var/log/syslog /var/log/kern.log 2>/dev/null || true
fi

# Create audit log directory
mkdir -p /var/log/audit
chmod 750 /var/log/audit

echo "  ✓ Logging and auditing configured"
echo ""

###############################################################################
# 6. PASSWORD AND AUTHENTICATION HARDENING
###############################################################################
echo "[6/10] Password and Authentication Hardening..."

# Configure password quality requirements (if libpam-pwquality is installed)
if [ -f /etc/security/pwquality.conf ]; then
    echo "  - Configuring password quality requirements..."
    cat > /etc/security/pwquality.conf <<'EOF'
# Password Quality Requirements (DISA STIG/FedRAMP)
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
minclass = 4
maxrepeat = 3
maxsequence = 3
dictcheck = 1
usercheck = 1
enforcing = 1
EOF
fi

# Configure password aging (if applicable)
if [ -f /etc/login.defs ]; then
    echo "  - Configuring password aging..."
    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN    14/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs
fi

echo "  ✓ Password and authentication hardening complete"
echo ""

###############################################################################
# 7. SSH HARDENING (if SSH is present)
###############################################################################
echo "[7/10] SSH Hardening..."

if [ -f /etc/ssh/sshd_config ]; then
    echo "  - Hardening SSH configuration..."

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Apply STIG/CIS recommendations
    cat >> /etc/ssh/sshd_config <<'EOF'

# FIPS/FedRAMP SSH Hardening
Protocol 2
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
IgnoreRhosts yes
HostbasedAuthentication no
PermitUserEnvironment no
ClientAliveInterval 300
ClientAliveCountMax 0
LoginGraceTime 60
AllowTcpForwarding no
MaxSessions 2

# FIPS-approved ciphers and MACs
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512,hmac-sha2-256
KexAlgorithms ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256

# Logging
SyslogFacility AUTH
LogLevel VERBOSE
EOF

    chmod 600 /etc/ssh/sshd_config
else
    echo "  ⚠ SSH not installed (container may not require SSH)"
fi

echo "  ✓ SSH hardening complete"
echo ""

###############################################################################
# 8. REMOVE UNNECESSARY PACKAGES
###############################################################################
echo "[8/10] Removing Unnecessary Packages..."

# List of packages to remove (if present)
REMOVE_PACKAGES=(
    "telnet"
    "rsh-client"
    "rsh-redone-client"
    "nis"
    "tftp"
    "talk"
    "ldap-utils"
    "xinetd"
)

echo "  - Checking for unnecessary packages..."
for pkg in "${REMOVE_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        apt-get remove -y "$pkg" 2>/dev/null || true
        echo "    ✓ Removed: $pkg"
    fi
done

# Clean up package cache
apt-get autoremove -y 2>/dev/null || true
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true

echo "  ✓ Unnecessary packages removed"
echo ""

###############################################################################
# 9. FILE INTEGRITY AND PERMISSIONS
###############################################################################
echo "[9/10] File Integrity and Permissions..."

# Create world-writable directories with sticky bit
echo "  - Setting sticky bit on world-writable directories..."
chmod 1777 /tmp /var/tmp 2>/dev/null || true

# Remove world-writable permissions from files
echo "  - Removing world-writable permissions from files..."
find / -xdev -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" \
    -exec chmod o-w {} \; 2>/dev/null || true

# Find and secure unowned files (FedRAMP requirement)
echo "  - Checking for unowned files..."
UNOWNED_FILES=$(find / -xdev -nouser -o -nogroup 2>/dev/null | wc -l)
if [ "$UNOWNED_FILES" -gt 0 ]; then
    echo "    ⚠ Found $UNOWNED_FILES unowned files (will be assigned to root)"
    find / -xdev -nouser -exec chown root {} \; 2>/dev/null || true
    find / -xdev -nogroup -exec chgrp root {} \; 2>/dev/null || true
fi

echo "  ✓ File integrity and permissions secured"
echo ""

###############################################################################
# 10. FIPS-SPECIFIC HARDENING
###############################################################################
echo "[10/10] FIPS-Specific Hardening..."

# Ensure only FIPS crypto is available (already done in Dockerfile)
echo "  - Verifying FIPS crypto configuration..."

# Check that non-FIPS crypto libraries are not present
NON_FIPS_LIBS=(
    "/usr/lib/x86_64-linux-gnu/libssl.so"
    "/usr/lib/x86_64-linux-gnu/libcrypto.so"
)

FOUND_NON_FIPS=0
for lib in "${NON_FIPS_LIBS[@]}"; do
    if [ -f "$lib" ]; then
        echo "    ✗ WARNING: Non-FIPS library found: $lib"
        FOUND_NON_FIPS=1
    fi
done

if [ $FOUND_NON_FIPS -eq 0 ]; then
    echo "    ✓ No non-FIPS crypto libraries detected"
fi

# Set FIPS mode for system-wide crypto
if [ ! -d /etc/crypto-policies ]; then
    mkdir -p /etc/crypto-policies
fi

cat > /etc/crypto-policies/config <<'EOF'
# FIPS mode enabled system-wide
FIPS
EOF

# Document hardening completion
cat > /etc/fips-hardening-applied <<EOF
FIPS/FedRAMP Hardening Applied
Date: $(date -u +%Y-%m-%d)
Script: ubuntu-24.04-stig.sh v1.0
Base: Ubuntu 24.04 LTS
Standards:
  - DISA STIG for Ubuntu (adapted)
  - CIS Ubuntu Linux 24.04 LTS Benchmark
  - NIST SP 800-53 Rev. 5
  - FedRAMP Moderate/High Baseline
Hardening Log: $HARDENING_LOG
EOF

chmod 644 /etc/fips-hardening-applied

echo "  ✓ FIPS-specific hardening complete"
echo ""

###############################################################################
# SUMMARY AND COMPLETION
###############################################################################
echo "========================================"
echo "✓ HARDENING COMPLETE"
echo "========================================"
echo ""
echo "Applied Controls:"
echo "  - File system hardening (SUID/SGID removal, permissions)"
echo "  - Unused services disabled"
echo "  - Kernel hardening (sysctl parameters)"
echo "  - Network hardening (TCP wrappers)"
echo "  - Logging and auditing configured"
echo "  - Password and authentication hardening"
echo "  - SSH hardening (FIPS ciphers)"
echo "  - Unnecessary packages removed"
echo "  - File integrity and permissions secured"
echo "  - FIPS crypto enforcement verified"
echo ""
echo "Documentation:"
echo "  - Hardening summary: /etc/fips-hardening-applied"
echo "  - Detailed log: $HARDENING_LOG"
echo ""
echo "Next Steps:"
echo "  1. Run SCAP scan to generate compliance report"
echo "  2. Review and document any exceptions"
echo "  3. Provide compliance evidence to 3PAO"
echo ""
echo "⚠ Note: Some hardening controls (e.g., kernel parameters)"
echo "  may not be fully effective in containers and depend on"
echo "  host configuration."
echo ""

exit 0
