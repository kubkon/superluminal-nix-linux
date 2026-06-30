# Superluminal Nix flake

Use this flake to run the Linux Superluminal distribution on NixOS. The flake fetches the official Superluminal Linux tarball and patches its ELF binaries/libraries/plugins with Nix runtime paths.

This currently targets `x86_64-linux`, matching the bundled Superluminal Linux binaries.

## Usage

1. Clone this repository:

```sh
git clone git@github.com:kubkon/superluminal-nix-linux.git
cd superluminal-nix-linux
```

2. Build, run, or enter the dev shell:

```sh
nix build
```

```sh
nix run
```

```sh
nix develop
```

To run the command-line tool:

```sh
nix run .#superluminalcmd -- --help
```

To install the wrapper scripts into your Nix profile:

```sh
nix profile install .#superluminal
```

## Notes

- The package source is fetched from `https://superluminal.blob.core.windows.net/public-installers/SuperluminalLinux-1.0.7510.599-alpha.tar.gz` with a fixed SHA-256 hash.
- `nix build` builds the package into the Nix store and creates a local `result` symlink; it does not install the package into your user profile.
- `nix develop` provides patching/debugging tools such as `patchelf`, `file`, `scanelf`, `strace`, and `gdb`.
- On non-NixOS systems, OpenGL may still require `nixGL` or another host-GL wrapper, depending on your graphics driver setup.

## Capturing from the UI

Superluminal's Linux known issues state that capturing from the UI requires a graphical PolicyKit agent. Without one, capture startup can fail with an unclear error.

On NixOS, make sure PolicyKit is enabled and that your desktop session starts an authentication agent. Desktop environments often do this for you; custom/window-manager sessions often do not.

For example, in a NixOS module:

```nix
{ pkgs, ... }:
{
  security.polkit.enable = true;

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "PolicyKit authentication agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
    };
  };
}
```

This flake does not package or install PolicyKit. On NixOS, configure PolicyKit system-wide instead. `pkexec` should normally resolve to the setuid host wrapper at `/run/wrappers/bin/pkexec`, and a graphical authentication agent must be running in your logged-in session.

You can check the host-side requirements with:

```sh
command -v pkexec
ps -eo pid,comm,args | grep -E 'polkit|PolicyKit|authentication-agent' | grep -v grep
```

If attach still fails, inspect:

```text
~/.config/Superluminal/Profiler/SuperluminalPerformance.log
~/.config/Superluminal/Profiler/CaptureService.log
~/.config/Superluminal/Profiler/CaptureService.wrapper.log
```

If `SuperluminalPerformance.log` says the capture service exited with code `127` but `CaptureService.wrapper.log` is missing, the capture-service wrapper was probably never reached. On NixOS this usually means `pkexec` failed before exec'ing the wrapper, most commonly because no graphical PolicyKit authentication agent is running in the user session.
