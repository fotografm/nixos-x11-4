{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Bootloader (UEFI + systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Nix daemon: flakes, store optimisation, and weekly GC
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Hostname
  networking.hostName = "x11-4";

  # Static IP on 192.168.8.0/24
  # eno1 is enslaved to br0 so Incus containers/VMs can sit on the real LAN.
  # The host's IP lives on br0, not eno1.
  # Verify NIC name with `ip -brief link` and change `eno1` if needed.
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  networking.bridges.br0.interfaces = [ "eno1" ];

  networking.interfaces.br0.ipv4.addresses = [{
    address = "192.168.8.50";
    prefixLength = 24;
  }];

  networking.defaultGateway = "192.168.8.1";
  networking.nameservers = [ "192.168.8.70" "1.1.1.1" ];

  # Incus requires nftables (not iptables) on NixOS
  networking.nftables.enable = true;

  # Open the Incus HTTPS API/UI port so pavi-mint can reach it
  networking.firewall.allowedTCPPorts = [ 22 8443 ];

  # Incus itself, declaratively initialised.
  # Uses /dev/sda3 as a btrfs storage pool, and attaches the default
  # profile's eth0 to br0 so containers/VMs get IPs from the LAN DHCP.
  # No incusbr0 (NATted bridge) is created.
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    preseed = {
      storage_pools = [
        {
          name = "default";
          driver = "btrfs";
          config = {
            source = "/dev/sda3";
          };
        }
      ];
      profiles = [
        {
          name = "default";
          devices = {
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
            eth0 = {
              name = "eth0";
              nictype = "bridged";
              parent = "br0";
              type = "nic";
            };
          };
        }
      ];
    };
  };

  # Locale / time
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  # User
  users.users.user = {
    isNormalUser = true;
    extraGroups = [ "wheel" "incus-admin" ];
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... user@h510"
    ];
  };

  # Allow wheel sudo without password (convenient on a test box)
  security.sudo.wheelNeedsPassword = false;

  # SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
    settings.PasswordAuthentication = true;
  };

  # Tailscale — joins the tailnet as a regular node.
  # No subnet routing here (ct106/vm101/s740-c38 handle that already).
  services.tailscale.enable = true;

  # Minimal toolset
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    btop
    tmux
    cmatrix
    incus
    btrfs-progs
  ];

  # First release this config targets — do not change after install
  system.stateVersion = "26.05";
}
