# Local testing configuration
registry_name := "blue-build-registry"
registry_port := "5000"
image_name := "aurora-dx-gorschu"
local_registry := "localhost:" + registry_port
vm_name := "blue-build-test"

# List available recipes
default:
    @just --list

# Start local OCI registry
registry-start:
    #!/usr/bin/env bash
    if podman ps --format '{{{{.Names}}}}' | grep -q "{{registry_name}}"; then
        echo "Registry already running"
    else
        echo "Starting local registry on port {{registry_port}}..."
        podman run -d --replace --name {{registry_name}} \
            -p {{registry_port}}:5000 \
            docker.io/library/registry:2
    fi

# Stop local OCI registry
registry-stop:
    podman stop {{registry_name}} || true
    podman rm {{registry_name}} || true

# Build and push an image (recipe can be 'aurora' or 'bluefin', registry defaults to local)
build-push recipe registry=local_registry:
    #!/usr/bin/env bash
    if [ "{{registry}}" = "local_registry" ]; then
        just registry-start
        REGISTRY="{{local_registry}}"
    else
        REGISTRY="{{registry}}"
    fi
    bluebuild build --push --cache-layers --quiet --registry "$REGISTRY" --registry-namespace gorschu --compression-format zstd recipes/recipe-{{recipe}}.yml --build-driver podman

# Install VM from ISO using virt-install
vm-install:
    #!/usr/bin/env bash
    ISO_PATH="/var/lib/libvirt/images/bluefin-stable-x86_64.iso"
    DISK_PATH="/var/lib/libvirt/images/{{vm_name}}.qcow2"

    if [ ! -f "$ISO_PATH" ]; then
        echo "Error: $ISO_PATH not found"
        echo "Please copy the ISO to /var/lib/libvirt/images/"
        exit 1
    fi
    if [ ! -f "$DISK_PATH" ]; then
        echo "Creating VM disk image..."
        sudo qemu-img create -f qcow2 "$DISK_PATH" 50G
    fi
    echo "Installing VM with virt-install..."
    virt-install \
        --connect qemu:///system \
        --name {{vm_name}} \
        --memory 8192 \
        --vcpus 12 \
        --disk path="$DISK_PATH",format=qcow2 \
        --cdrom "$ISO_PATH" \
        --os-variant fedora-rawhide \
        --graphics spice \
        --network network=default

# Start existing VM
vm-start:
    virsh --connect qemu:///system start {{vm_name}}
    virt-viewer --connect qemu:///system {{vm_name}}

# Rebase VM to local registry image
vm-rebase:
    #!/usr/bin/env bash
    HOST_IP=$(ip -4 addr show virbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "192.168.122.1")
    echo "Rebasing VM to local registry image..."
    echo "Run this inside the VM:"
    echo "  sudo bootc switch $HOST_IP:{{registry_port}}/gorschu/aurora-dx-gorschu:stable"
    echo "  # or for bluefin:"
    echo "  sudo bootc switch $HOST_IP:{{registry_port}}/gorschu/bluefin-dx-gorschu:stable"

# Full workflow: build, push, and show rebase instructions
test recipe: (build-push recipe)
    #!/usr/bin/env bash
    HOST_IP=$(ip -4 addr show virbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "192.168.122.1")
    echo ""
    echo "Image pushed to {{local_registry}}/gorschu/{{recipe}}-dx-gorschu:stable"
    echo ""
    echo "To rebase your VM, run inside it:"
    echo "  sudo bootc switch $HOST_IP:{{registry_port}}/gorschu/{{recipe}}-dx-gorschu:stable"

# Clean up everything
clean: registry-stop
    @echo "Cleaned up local registry"
