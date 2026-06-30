# Superluminal Nix flake

If you want to use prepackaged Superluminal app on NixOS, you can use this flake.

## Steps

1. Clone this repo

```
git clone git@github.com:kubkon/superluminal-nix-linux && cd superluminal-nix-linux
```

2. Download and unpack Superluminal into the repo dir

```
wget https://superluminal.blob.core.windows.net/public-installers/SuperluminalLinux-1.0.7510.599-alpha.tar.gz
tar xvf SuperluminalLinux-1.0.7510.599-alpha.tar.gz
```

3. Run!

```
nix develop
nix run
```

Or install into the Nix store

```
nix build  
```
