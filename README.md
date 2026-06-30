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
