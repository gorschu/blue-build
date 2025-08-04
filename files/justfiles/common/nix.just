gorschu-install-nix:
    #!/usr/bin/bash
    [[ -d /var/home/nix ]] && echo "nix already installed - /var/home/nix is present!" && exit 1
    [[ ! -f /etc/.rpm-ostree-transient ]] && sudo touch /etc/.rpm-ostree-transient && \
      echo "Preparing rpm-ostree transient root - will reboot" && sudo rpm-ostree initramfs-etc --reboot --track=/etc/ostree/prepare-root.conf
    echo "Installing nix" && \
      curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate
    echo "trusted-users = root $(id --name --user)" | sudo tee -a /etc/nix/nix-custom.conf
    echo "undoing rpm-ostree modifications (transient root)"
    sudo rpm-ostree reset && sudo rm /etc/.rpm-ostree-transient
