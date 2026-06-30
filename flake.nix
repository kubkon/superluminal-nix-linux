{
  description = "Nix package and development shell for the bundled Superluminal Linux distribution";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;

          runtimeLibs = with pkgs; [
            # Core runtime libraries missing from the upstream bundle on NixOS.
            stdenv.cc.cc.lib
            glib
            dbus
            expat
            zlib

            # OpenGL / EGL. On non-NixOS hosts this may still need nixGL or an
            # equivalent wrapper so libGL can reach the host graphics driver.
            libglvnd
            mesa
            libdrm

            # Font/image/text stack used directly or through Qt/GTK plugins.
            fontconfig
            freetype
            harfbuzz
            libpng
            libjpeg
            libtiff
            pcre2

            # X11 and xcb stack for Qt's xcb platform plugin.
            libxkbcommon
            xkeyboard_config
            libice
            libsm
            libx11
            libxscrnsaver
            libxau
            libxcomposite
            libxcursor
            libxdamage
            libxdmcp
            libxext
            libxfixes
            libxi
            libxinerama
            libxrandr
            libxrender
            libxtst
            libxcb
            libxcb-util
            libxcb-cursor
            libxcb-errors
            libxcb-image
            libxcb-keysyms
            libxcb-render-util
            libxcb-wm

            # The bundled Qt distribution ships a gtk3 platform theme plugin.
            gtk3
            gdk-pixbuf
            cairo
            pango
            atk
            at-spi2-core
          ];

          runtimeLibraryPath = lib.makeLibraryPath runtimeLibs;
          dynamicLinker = pkgs.stdenv.cc.bintools.dynamicLinker;

          superluminal = pkgs.stdenvNoCC.mkDerivation {
            pname = "superluminal";
            version = "local";

            src = lib.cleanSourceWith {
              src = ./.;
              filter = path: type:
                let
                  base = baseNameOf path;
                in
                !(base == ".git" || lib.hasPrefix "result" base);
            };

            nativeBuildInputs = with pkgs; [
              makeWrapper
              patchelf
            ];

            dontConfigure = true;
            dontBuild = true;
            dontStrip = true;
            # We do the binary patching ourselves below. Avoid the generic fixup
            # pass shrinking the intentionally broad RPATHs needed by dlopen'd
            # Qt/slPlugins modules.
            dontPatchELF = true;

            installPhase = ''
              runHook preInstall

              appDir="$out/opt/superluminal"
              mkdir -p "$appDir" "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/scalable/apps"
              cp -a . "$appDir/"
              chmod -R u+w "$appDir"

              # Keep Nix build inputs out of the installed vendor payload.
              rm -f "$appDir/flake.nix" "$appDir/flake.lock"

              # Patch every ELF file we can find. Superluminal ships a large
              # bundle of executables, shared libraries, Qt plugins, and its own
              # slPlugins tree, so relying on top-level wrapper LD_LIBRARY_PATH is
              # not enough for dlopen'd plugins.
              rpath="${runtimeLibraryPath}:$appDir:$appDir/Qt/lib:\$ORIGIN:\$ORIGIN/..:\$ORIGIN/../..:\$ORIGIN/../../..:\$ORIGIN/Qt/lib:\$ORIGIN/../../lib:\$ORIGIN/../../Qt/lib"

              find "$appDir" -type f \
                \( -perm -0100 -o -name '*.so' -o -name '*.so.*' -o -name 'Superluminal*' \) \
                -print0 |
              while IFS= read -r -d "" elf; do
                if patchelf --print-rpath "$elf" >/dev/null 2>&1; then
                  echo "patching $elf"
                  patchelf --set-rpath "$rpath" "$elf"

                  if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
                    patchelf --set-interpreter "${dynamicLinker}" "$elf"
                  fi
                fi
              done

              commonWrapperArgs=(
                --set QT_PLUGIN_PATH "$appDir/Qt/plugins"
                --set QT_XKB_CONFIG_ROOT "${pkgs.xkeyboard_config}/share/X11/xkb"
                --prefix XDG_DATA_DIRS : "${pkgs.gtk3}/share:${pkgs.gsettings-desktop-schemas}/share:${pkgs.hicolor-icon-theme}/share"
                --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}:$appDir:$appDir/Qt/lib"
              )

              makeWrapper "$appDir/Superluminal" "$out/bin/superluminal" "''${commonWrapperArgs[@]}"
              makeWrapper "$appDir/SuperluminalCmd" "$out/bin/superluminalcmd" "''${commonWrapperArgs[@]}"
              makeWrapper "$appDir/SuperluminalCaptureService" "$out/bin/superluminal-capture-service" "''${commonWrapperArgs[@]}"
              makeWrapper "$appDir/SuperluminalCrashReporter" "$out/bin/superluminal-crash-reporter" "''${commonWrapperArgs[@]}"
              makeWrapper "$appDir/SuperluminalAutoUpdater" "$out/bin/superluminal-auto-updater" "''${commonWrapperArgs[@]}"

              install -Dm0644 "$appDir/Documentation/Superluminal/assets/img/logo.svg" \
                "$out/share/icons/hicolor/scalable/apps/superluminal.svg"

              cat > "$out/share/applications/superluminal.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Superluminal
Comment=Superluminal Performance profiler
Exec=$out/bin/superluminal
Icon=superluminal
Categories=Development;Profiling;
Terminal=false
EOF

              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck

              appDir="$out/opt/superluminal"
              ${pkgs.glibc.bin}/bin/ldd \
                "$appDir/Superluminal" \
                "$appDir/SuperluminalCmd" \
                "$appDir/SuperluminalCaptureService" \
                "$appDir/SuperluminalCrashReporter" \
                "$appDir/SuperluminalAutoUpdater" | tee ldd.log
              if grep -q 'not found' ldd.log; then
                echo "unresolved shared-library dependencies remain" >&2
                exit 1
              fi

              runHook postInstallCheck
            '';

            meta = {
              description = "Superluminal Performance profiler packaged from a local vendor bundle";
              homepage = "https://superluminal.eu/";
              platforms = [ "x86_64-linux" ];
              mainProgram = "superluminal";
            };
          };
        in
        {
          default = superluminal;
          superluminal = superluminal;
        });

      apps = forAllSystems (system:
        let
          pkg = self.packages.${system}.default;
        in
        {
          default = {
            type = "app";
            program = "${pkg}/bin/superluminal";
          };
          superluminalcmd = {
            type = "app";
            program = "${pkg}/bin/superluminalcmd";
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          lib = pkgs.lib;
          runtimeLibs = with pkgs; [
            stdenv.cc.cc.lib
            glib
            dbus
            expat
            zlib
            libglvnd
            mesa
            libdrm
            fontconfig
            freetype
            harfbuzz
            libpng
            libjpeg
            libtiff
            pcre2
            libxkbcommon
            xkeyboard_config
            libice
            libsm
            libx11
            libxscrnsaver
            libxau
            libxcomposite
            libxcursor
            libxdamage
            libxdmcp
            libxext
            libxfixes
            libxi
            libxinerama
            libxrandr
            libxrender
            libxtst
            libxcb
            libxcb-util
            libxcb-cursor
            libxcb-errors
            libxcb-image
            libxcb-keysyms
            libxcb-render-util
            libxcb-wm
            gtk3
            gdk-pixbuf
            cairo
            pango
            atk
            at-spi2-core
          ];
          runtimeLibraryPath = lib.makeLibraryPath runtimeLibs;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              patchelf
              binutils
              file
              pax-utils
              lsof
              strace
              gdb
              makeWrapper
              pkg-config
            ] ++ runtimeLibs;

            SUPERLUMINAL_RUNTIME_LIBRARY_PATH = runtimeLibraryPath;
            QT_XKB_CONFIG_ROOT = "${pkgs.xkeyboard_config}/share/X11/xkb";

            shellHook = ''
              export QT_PLUGIN_PATH="$PWD/Qt/plugins"
              export LD_LIBRARY_PATH="$SUPERLUMINAL_RUNTIME_LIBRARY_PATH:$PWD:$PWD/Qt/lib:''${LD_LIBRARY_PATH:-}"
              echo "Superluminal dev shell"
              echo "  Build package: nix build"
              echo "  Run GUI:       nix run"
              echo "  Run CLI:       nix run .#superluminalcmd -- --help"
              echo "  Inspect deps:  scanelf -n Superluminal SuperluminalCmd"
            '';
          };
        });
    };
}
