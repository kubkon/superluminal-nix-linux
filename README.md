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

## Releases

Available releases are listed in `releases.json` and exported as versioned flake packages. Build or run a specific release using its version:

```sh
nix build '.#"1.0.7510.599-alpha"'
```

```sh
nix run '.#"1.0.7510.599-alpha"'
```

`default`, `latest`, and `superluminal` all select the newest version in `releases.json`, as determined by Nix's version comparison:

```sh
nix build
nix build .#latest
nix build .#superluminal
```

When consuming this repository as a flake input, select the derivation through the package set:

```nix
superluminal.packages.${system}."1.0.7510.599-alpha"
```

To add a release, append its version, official archive URL, and fixed SHA-256 hash to `releases.json`. It automatically becomes `default`, `latest`, and `superluminal` when its version is newer than every existing entry.

## Notes

- Each entry in `releases.json` contains the official archive URL and its fixed SHA-256 hash.
- `nix build` builds the package into the Nix store and creates a local `result` symlink; it does not install the package into your user profile.
- `nix develop` provides patching/debugging tools such as `patchelf`, `file`, `scanelf`, `strace`, and `gdb`.
- On non-NixOS systems, OpenGL may still require `nixGL` or another host-GL wrapper, depending on your graphics driver setup.

## Qt / Wayland / scaling notes

The upstream Linux alpha currently ships Qt's XCB platform plugin, but not Qt's Wayland platform plugin. The GUI wrapper therefore forces:

```sh
QT_QPA_PLATFORM=xcb
```

This avoids log messages like:

```text
qt.qpa.plugin: Could not find the Qt platform plugin "wayland" in ""
```

The wrapper also unsets `QT_STYLE_OVERRIDE` so host Qt themes such as `kvantum` are not applied to Superluminal's bundled Qt tree.

If the GUI is still too small under Wayland/XWayland, use the Superluminal wrapper's convenience scale knob:

```sh
SUPERLUMINAL_SCALE=1.5 nix run
```

or:

```sh
SUPERLUMINAL_SCALE=2 nix run
```

This sets `QT_SCALE_FACTOR` and common `QT_FONT_DPI` values. If text is still too small, try overriding font DPI directly:

```sh
QT_FONT_DPI=192 nix run
```

or combine both:

```sh
SUPERLUMINAL_SCALE=2 QT_FONT_DPI=192 nix run
```

As a last-resort fallback for older Qt scaling behavior, the deprecated `QT_DEVICE_PIXEL_RATIO` path is available behind an explicit opt-in:

```sh
SUPERLUMINAL_SCALE=2 SUPERLUMINAL_LEGACY_DEVICE_PIXEL_RATIO=1 nix run
```

That mode may print a Qt deprecation warning.

## Capturing from the UI

Superluminal's Linux known issues state that capturing from the UI requires a graphical PolicyKit agent. Without one, capture startup can fail with an unclear error.

On NixOS, make sure PolicyKit is enabled and that your desktop session starts an authentication agent. Desktop environments often do this for you; custom/window-manager sessions often do not.

Starting with NixOS 26.11, enabling PolicyKit no longer enables the setuid `pkexec` wrapper by default. Superluminal uses `pkexec` to start its capture service with root privileges, so the wrapper must be enabled explicitly.

For example, in a NixOS module:

```nix
{ pkgs, ... }:
{
  security.polkit = {
    enable = true;
    enablePkexecWrapper = true;
  };

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

This flake does not package or install PolicyKit. On NixOS, configure PolicyKit system-wide instead. `pkexec` should resolve to the setuid host wrapper at `/run/wrappers/bin/pkexec`, and a graphical authentication agent must be running in your logged-in session.

You can check the host-side requirements with:

```sh
command -v pkexec
ls -l /run/wrappers/bin/pkexec
/run/wrappers/bin/pkexec id
ps -eo pid,comm,args | grep -E 'polkit|PolicyKit|authentication-agent' | grep -v grep
```

If `/run/wrappers/bin/pkexec` is missing and running `pkexec` prints `pkexec must be setuid root`, enable `security.polkit.enablePkexecWrapper` and rebuild the NixOS configuration. The non-setuid executable under `/run/current-system/sw/bin/pkexec` cannot elevate privileges on its own.

If attach still fails, inspect:

```text
~/.config/Superluminal/Profiler/SuperluminalPerformance.log
~/.config/Superluminal/Profiler/CaptureService.log
~/.config/Superluminal/Profiler/CaptureService.wrapper.log
```

If `SuperluminalPerformance.log` says the capture service exited with code `127` but `CaptureService.wrapper.log` has no entry for the attempt, the capture-service wrapper was never reached. Check that the setuid `pkexec` wrapper is enabled first, then check that a graphical PolicyKit authentication agent is running in the user session.
