#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/opt/proxmox-template-builder"
IMAGE_DIR="$BASE_DIR/images"

SNIPPET_DIR="/var/lib/vz/snippets"
CLOUDINIT_FILE="$BASE_DIR/cloud-init.yaml"

TEMPLATE_ID=9000
TEMPLATE_NAME="alma9-template"
TEMPLATE_VERSION="v1"

VM_NAME="${TEMPLATE_NAME}-${TEMPLATE_VERSION}"

IMAGE_NAME="AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/${IMAGE_NAME}"
CHECKSUM_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/CHECKSUM"

CHECKSUM_FILE="$IMAGE_DIR/CHECKSUM"
TMP_IMAGE="$IMAGE_DIR/$IMAGE_NAME.tmp"

STORAGE="ceph_data"
BRIDGE="vmbr0"

FORCE_REBUILD=false

while getopts ":f" opt; do
  case ${opt} in
    f )
      FORCE_REBUILD=true
      ;;
    \? )
      echo "Usage: $0 [-f]"
      exit 1
      ;;
  esac
done

echo "Creating folder structure"

mkdir -p "$BASE_DIR"
mkdir -p "$IMAGE_DIR"
mkdir -p "$SNIPPET_DIR"

echo "Generating cloud-init config"

cat > "$CLOUDINIT_FILE" <<EOF
#cloud-config

preserve_hostname: false
timezone: Europe/Zurich

ssh_pwauth: true



package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - cloud-utils-growpart
  - git
  - curl
  - vim

runcmd:
  - systemctl enable --now qemu-guest-agent
  - truncate -s 0 /etc/machine-id
  - rm -f /var/lib/dbus/machine-id
  - rm -f /etc/ssh/ssh_host_*
  - cloud-init clean
  - rm -rf /var/lib/cloud/*

power_state:
  mode: poweroff
EOF

echo "Fetching remote checksum"

wget -qO "$CHECKSUM_FILE" "$CHECKSUM_URL"

REMOTE_SUM=$(grep "$IMAGE_NAME" "$CHECKSUM_FILE" | awk '{print $1}')

download_image() {

    echo "Downloading AlmaLinux image"

    wget -O "$TMP_IMAGE" "$IMAGE_URL"

    DOWNLOADED_SUM=$(sha256sum "$TMP_IMAGE" | awk '{print $1}')

    if [ "$DOWNLOADED_SUM" != "$REMOTE_SUM" ]; then
        echo "Checksum mismatch, aborting"
        rm -f "$TMP_IMAGE"
        exit 1
    fi

    mv "$TMP_IMAGE" "$IMAGE_DIR/$IMAGE_NAME"

    echo "Image downloaded and verified"
}

if [ -f "$IMAGE_DIR/$IMAGE_NAME" ]; then

    LOCAL_SUM=$(sha256sum "$IMAGE_DIR/$IMAGE_NAME" | awk '{print $1}')

    if [ "$LOCAL_SUM" = "$REMOTE_SUM" ]; then
        echo "Image already up to date"
    else
        echo "Image outdated"
        download_image
    fi

else

    echo "Image not present"
    download_image

fi

echo "Copying cloud-init snippet"

cp "$CLOUDINIT_FILE" "$SNIPPET_DIR/alma9-template.yaml"

if qm status "$TEMPLATE_ID" >/dev/null 2>&1; then

    if [ "$FORCE_REBUILD" = true ]; then
        echo "Removing existing template"
        qm destroy "$TEMPLATE_ID" --purge
    else
        echo "Template already exists"
        echo "Run script with -f to rebuild"
        exit 1
    fi

fi

echo "Creating VM"

qm create "$TEMPLATE_ID" \
  --name "$VM_NAME" \
  --memory 2048 \
  --cores 2 \
  --cpu max \
  --net0 virtio,bridge="$BRIDGE"

echo "Configuring disks"

qm set "$TEMPLATE_ID" \
  --scsihw virtio-scsi-single \
  --scsi0 "$STORAGE:0,import-from=$IMAGE_DIR/$IMAGE_NAME,discard=on,iothread=1"
qm set "$TEMPLATE_ID" --scsi1 "$STORAGE:cloudinit"

qm set "$TEMPLATE_ID" --bootdisk scsi0
qm set "$TEMPLATE_ID" --boot order=scsi0

echo "Configuring VM hardware"

qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
qm set "$TEMPLATE_ID" --balloon 0
qm set "$TEMPLATE_ID" --agent enabled=1

echo "Configuring cloud-init"

qm set "$TEMPLATE_ID" --ipconfig0 ip=dhcp

qm set "$TEMPLATE_ID" \
  --cicustom "user=local:snippets/alma9-template.yaml"

echo "Booting VM for provisioning"

qm start "$TEMPLATE_ID"

echo "Waiting for shutdown"

timeout=900
elapsed=0

while qm status "$TEMPLATE_ID" | grep -q running; do
    sleep 5
    elapsed=$((elapsed+5))

    if [ $elapsed -gt $timeout ]; then
        echo "Timeout waiting for shutdown, stopping VM"
        qm stop "$TEMPLATE_ID"
        break
    fi
done

echo "Converting VM to template"

qm template "$TEMPLATE_ID"

echo "Template $VM_NAME created successfully"