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
  # Verify interface name with `ip -brief link` on the live env
  # and change `eno1` below if needed.
  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  networking.interfaces.eno1.ipv4.addresses = [{
    address = "192.168.8.50";
    prefixLength = 24;
  }];

  networking.defaultGateway = "192.168.8.1";
  networking.nameservers = [ "192.168.8.70" "1.1.1.1" ];

  # Incus requires nftables (not iptables) on NixOS
  networking.nftables.enable = true;

  # Incus itself
  virtualisation.incus.enable = true;

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
