#!/bin/sh
set -eu
ROOTFS=/work/rootfs

# Wolfi uses different repository structures. 
# We use the official Wolfi repositories.
mkdir -p "$ROOTFS/etc/apk"
cat > "$ROOTFS/etc/apk/repositories" <<REPO
https://ghcr.io/wolfi-dev/apk
REPO

# We use apk --root to populate the Wolfi rootfs.
# Note: Wolfi packages may have different names than Alpine.
# We map the essential Podroid requirements to Wolfi packages.
apk -U --allow-untrusted --root "$ROOTFS" --initdb add \
    wolfi-base \
    bash \
    podman \
    crun \
    fuse-overlayfs \
    iptables \
    ip6tables \
    nftables \
    bridge-utils \
    iproute2 \
    dropbear \
    openssh-sftp-server \
    curl \
    ca-certificates \
    shadow \
    slirp4netns \
    aardvark-dns \
    netavark \
    libcap \
    sudo \
    gzip \
    xz \
    tigervnc \
    pulseaudio \
    pulseaudio-utils \
    font-dejavu

# --- Init System Transition ---
# Wolfi is not OpenRC-based by default. To keep the podroid-bootstrap 
# and existing service logic, we will install a minimal OpenRC 
# or a compatible shim. Since Podroid relies on /etc/init.d/, 
# we'll attempt to pull in openrc if available in Wolfi, 
# otherwise we will create a simple boot script.
apk -U --allow-untrusted --root "$ROOTFS" --initdb add openrc busybox-openrc || true

if [ ! -d "$ROOTFS/etc/init.d" ]; then
    echo "OpenRC not found in Wolfi, creating custom boot shim..."
    mkdir -p "$ROOTFS/etc/init.d"
    # Create a dummy OpenRC-like environment for the podroid scripts
    cat > "$ROOTFS/etc/init.d/rc" <<RC
#!/bin/sh
# Minimal boot shim to execute podroid services in order
for svc in podroid-bootstrap podroid-network podroid-resize podroid-ready podroid-x11 podroid-vsock podroid-hostd podroid-downloads podroid-migrate; do
    [ -x "$ROOTFS/etc/init.d/$svc" ] && "$ROOTFS/etc/init.d/$svc" start
done
RC
    chmod +x "$ROOTFS/etc/init.d/rc"
fi

# Apply file capabilities to newuidmap/newgidmap
if command -v setcap >/dev/null 2>&1; then
    setcap cap_setuid+ep "$ROOTFS/usr/bin/newuidmap" 2>/dev/null || true
    setcap cap_setgid+ep "$ROOTFS/usr/bin/newgidmap" 2>/dev/null || true
fi

# Sudo configuration
mkdir -p "$ROOTFS/etc/sudoers.d"
echo "%wheel ALL=(ALL) ALL" > "$ROOTFS/etc/sudoers.d/wheel"
chmod 0440 "$ROOTFS/etc/sudoers.d/wheel"

# Set root password to "podroid"
ROOT_HASH=$(openssl passwd -6 podroid)
# Ensure /etc/shadow exists before sed
touch "$ROOTFS/etc/shadow"
sed -i "s|^root:[^:]*:|root:${ROOT_HASH}:|" "$ROOTFS/etc/shadow"

# Strip docs/man/locale
rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/doc" \
       "$ROOTFS/usr/share/locale" "$ROOTFS/usr/share/info"

# Pre-create podman storage dirs
mkdir -p "$ROOTFS/var/lib/containers/storage" \
         "$ROOTFS/run/containers/storage" \
         "$ROOTFS/run/libpod" \
         "$ROOTFS/run/crun"

# Copy custom service files
cp /work/files/etc/init.d/podroid-bootstrap "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-network   "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-resize    "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-ready     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-x11       "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-vsock     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-hostd     "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-downloads "$ROOTFS/etc/init.d/"
cp /work/files/etc/init.d/podroid-migrate   "$ROOTFS/etc/init.d/"
chmod +x "$ROOTFS/etc/init.d/podroid-"*

# Copy /usr/local/bin scripts
mkdir -p "$ROOTFS/usr/local/bin"
cp /work/files/usr/local/bin/podroid-resize "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-login  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-getty  "$ROOTFS/usr/local/bin/"
cp /work/files/usr/local/bin/podroid-backup "$ROOTFS/usr/local/bin/"

chmod +x "$ROOTFS/usr/local/bin/podroid-vsock-agent" 2>/dev/null || true
chmod +x "$ROOTFS/usr/local/bin/podroid-hostd" 2>/dev/null || true
chmod +x "$ROOTFS/usr/local/bin/podroid-overlay-normalize" 2>/dev/null || true

ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-notify"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-forward"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-open"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-power"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-headless"
ln -sf podroid-hostd "$ROOTFS/usr/local/bin/podroid-server"
chmod +x "$ROOTFS/usr/local/bin/podroid-"*

# vsock agent config
mkdir -p "$ROOTFS/etc/podroid"
cp /work/files/etc/podroid/forwards.conf "$ROOTFS/etc/podroid/forwards.conf"
chmod 0644 "$ROOTFS/etc/podroid/forwards.conf"

mkdir -p "$ROOTFS/etc/podroid/migrations"
cp /work/files/etc/podroid/migrations/README "$ROOTFS/etc/podroid/migrations/README"
