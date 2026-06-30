{
  description = "Nix package and development shell for the Superluminal Linux distribution";

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
            elfutils

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
          helperPath = lib.makeBinPath (with pkgs; [
            coreutils
            gnugrep
            gawk
            procps
            util-linux
            which
          ]);
          dynamicLinker = pkgs.stdenv.cc.bintools.dynamicLinker;

          superluminal = pkgs.stdenvNoCC.mkDerivation {
            pname = "superluminal";
            version = "1.0.7510.599-alpha";

            # Fetch the official binary distribution instead of using ./. as
            # the source. In a Git flake, untracked files are intentionally not
            # included in the flake source, which makes packaging a locally
            # unpacked vendor bundle unreliable unless every binary is tracked.
            src = pkgs.fetchurl {
              url = "https://superluminal.blob.core.windows.net/public-installers/SuperluminalLinux-1.0.7510.599-alpha.tar.gz";
              hash = "sha256-fUcTGD6LvNtX0aQFeXJlMg4wdJmjyS8hJLGwsl3LZSo=";
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

              # The GUI starts the capture service by its absolute path under
              # opt/superluminal, bypassing the bin/ wrapper below. Keep a real
              # patched binary next to a small environment/logging wrapper at the
              # original path so spawned capture-service processes get the same
              # Nix runtime environment as the GUI.
              mv "$appDir/SuperluminalCaptureService" "$appDir/SuperluminalCaptureService.real"

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

              cat > "$appDir/SuperluminalCaptureService" <<EOF
#!${pkgs.runtimeShell}
appDir="$appDir"
export QT_PLUGIN_PATH="$appDir/Qt/plugins"
export QT_XKB_CONFIG_ROOT="${pkgs.xkeyboard_config}/share/X11/xkb"
export XDG_DATA_DIRS="${pkgs.gtk3}/share:${pkgs.gsettings-desktop-schemas}/share:${pkgs.hicolor-icon-theme}/share:\''${XDG_DATA_DIRS:-}"
export LD_LIBRARY_PATH="${runtimeLibraryPath}:$appDir:$appDir/Qt/lib:\''${LD_LIBRARY_PATH:-}"
export PATH="${helperPath}:\''${PATH:-}"

logDir=""
previousArg=""
for arg in "\$@"; do
  if [ "\$previousArg" = "--logFileDirectory" ]; then
    logDir="\$arg"
    break
  fi

  case "\$arg" in
    --logFileDirectory=*)
      logDir="\''${arg#--logFileDirectory=}"
      break
      ;;
  esac

  previousArg="\$arg"
done

if [ -z "\$logDir" ]; then
  logDir="\''${SUPERLUMINAL_CAPTURE_WRAPPER_LOG_DIR:-\''${XDG_CONFIG_HOME:-\''${HOME:-/tmp}/.config}/Superluminal/Profiler}"
fi

if ! mkdir -p "\$logDir" 2>/dev/null; then
  logDir="\''${TMPDIR:-/tmp}"
fi
logFile="\$logDir/CaptureService.wrapper.log"

if { : >> "\$logFile"; } 2>/dev/null; then
  {
    echo "--- SuperluminalCaptureService wrapper ---"
    date
    echo "cwd: \$(pwd)"
    echo "argv: \$0 \$*"
    echo "PATH: \$PATH"
    echo "pkexec: \$(command -v pkexec || true)"
  } >> "\$logFile" 2>&1 || true

  "\$appDir/SuperluminalCaptureService.real" "\$@" >> "\$logFile" 2>&1
  status="\$?"
  echo "exit status: \$status" >> "\$logFile" 2>&1 || true
else
  "\$appDir/SuperluminalCaptureService.real" "\$@"
  status="\$?"
fi

exit "\$status"
EOF
              chmod 0755 "$appDir/SuperluminalCaptureService"

              commonWrapperArgs=(
                --set QT_PLUGIN_PATH "$appDir/Qt/plugins"
                --set QT_XKB_CONFIG_ROOT "${pkgs.xkeyboard_config}/share/X11/xkb"
                --prefix XDG_DATA_DIRS : "${pkgs.gtk3}/share:${pkgs.gsettings-desktop-schemas}/share:${pkgs.hicolor-icon-theme}/share"
                --prefix LD_LIBRARY_PATH : "${runtimeLibraryPath}:$appDir:$appDir/Qt/lib"
                --prefix PATH : "${helperPath}"
              )

              cat > "$out/bin/superluminal" <<EOF
#!${pkgs.runtimeShell}
export QT_PLUGIN_PATH="$appDir/Qt/plugins"
export QT_XKB_CONFIG_ROOT="${pkgs.xkeyboard_config}/share/X11/xkb"
export XDG_DATA_DIRS="${pkgs.gtk3}/share:${pkgs.gsettings-desktop-schemas}/share:${pkgs.hicolor-icon-theme}/share:\''${XDG_DATA_DIRS:-}"
export LD_LIBRARY_PATH="${runtimeLibraryPath}:$appDir:$appDir/Qt/lib:\''${LD_LIBRARY_PATH:-}"
export PATH="${helperPath}:\''${PATH:-}"

# The upstream Linux alpha does not ship Qt's Wayland platform plugin. Use
# XCB/XWayland by default instead of letting Wayland sessions select a missing
# backend. Users can still override QT_QPA_PLATFORM explicitly.
export QT_QPA_PLATFORM="\''${QT_QPA_PLATFORM:-xcb}"

# Host Qt theme settings can reference plugins that are not in Superluminal's
# bundled Qt tree, e.g. QT_STYLE_OVERRIDE=kvantum.
unset QT_STYLE_OVERRIDE

export QT_ENABLE_HIGHDPI_SCALING="\''${QT_ENABLE_HIGHDPI_SCALING:-1}"

# Convenience knob for older Qt/XWayland setups where QT_SCALE_FACTOR alone may
# not affect Superluminal's custom-rendered UI. It sets modern Qt scaling and
# common font-DPI equivalents while still allowing explicit QT_* overrides.
if [ -n "\''${SUPERLUMINAL_SCALE:-}" ]; then
  if [ -z "\''${QT_SCALE_FACTOR:-}" ]; then
    export QT_SCALE_FACTOR="\$SUPERLUMINAL_SCALE"
  fi
  # QT_DEVICE_PIXEL_RATIO is deprecated and noisy on startup, so keep it opt-in
  # for machines that really need Qt's legacy scaling path.
  if [ -n "\''${SUPERLUMINAL_LEGACY_DEVICE_PIXEL_RATIO:-}" ] && [ -z "\''${QT_DEVICE_PIXEL_RATIO:-}" ]; then
    export QT_DEVICE_PIXEL_RATIO="\$SUPERLUMINAL_SCALE"
  fi
  if [ -z "\''${QT_AUTO_SCREEN_SCALE_FACTOR:-}" ]; then
    export QT_AUTO_SCREEN_SCALE_FACTOR=0
  fi
  if [ -z "\''${QT_FONT_DPI:-}" ]; then
    case "\$SUPERLUMINAL_SCALE" in
      1) export QT_FONT_DPI=96 ;;
      1.25) export QT_FONT_DPI=120 ;;
      1.5) export QT_FONT_DPI=144 ;;
      1.75) export QT_FONT_DPI=168 ;;
      2) export QT_FONT_DPI=192 ;;
      2.5) export QT_FONT_DPI=240 ;;
      3) export QT_FONT_DPI=288 ;;
    esac
  fi
else
  export QT_AUTO_SCREEN_SCALE_FACTOR="\''${QT_AUTO_SCREEN_SCALE_FACTOR:-1}"
fi

exec "$appDir/Superluminal" "\$@"
EOF
              chmod 0755 "$out/bin/superluminal"

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
              find "$appDir" -type f \
                \( -perm -0100 -o -name '*.so' -o -name '*.so.*' -o -name 'Superluminal*' \) \
                -print0 |
              while IFS= read -r -d "" elf; do
                if patchelf --print-rpath "$elf" >/dev/null 2>&1; then
                  echo "checking $elf"
                  ${pkgs.glibc.bin}/bin/ldd "$elf"
                fi
              done | tee ldd.log
              if grep -q 'not found' ldd.log; then
                echo "unresolved shared-library dependencies remain" >&2
                exit 1
              fi

              runHook postInstallCheck
            '';

            meta = {
              description = "Superluminal Performance profiler packaged from the official Linux binary distribution";
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
            elfutils
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
              export LD_LIBRARY_PATH="$SUPERLUMINAL_RUNTIME_LIBRARY_PATH:''${LD_LIBRARY_PATH:-}"
              echo "Superluminal dev shell"
              echo "  Build package: nix build"
              echo "  Run GUI:       nix run"
              echo "  Run CLI:       nix run .#superluminalcmd -- --help"
              echo "  Inspect deps:  nix build && scanelf -n result/opt/superluminal/Superluminal result/opt/superluminal/SuperluminalCmd"
            '';
          };
        });
    };
}
