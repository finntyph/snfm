{
  description = "snfm - Super Nintendo File Manager (send_file, manage_files)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # The `sni` git submodule, pinned to the commit snfm references.
    # Update this rev when the submodule pointer changes.
    sni-src = {
      url = "github:alttpo/sni/9a27ef06a6bd2c8a46fa571e5ed8dc32434e3ea1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, sni-src }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        snfm = pkgs.stdenv.mkDerivation {
          pname = "snfm";
          version = self.shortRev or self.dirtyShortRev or "unstable";
          src = self;

          nativeBuildInputs = with pkgs; [
            cmake
            pkg-config
            protobuf        # protoc
            grpc            # grpc_cpp_plugin
            wrapGAppsHook3  # GTK env for the wxWidgets GUI
          ];

          buildInputs = with pkgs; [
            grpc
            protobuf
            yaml-cpp
            wxwidgets_3_2
            gtk3
            abseil-cpp
            c-ares
            re2
            openssl
            zlib
          ];

          postPatch = ''
            # Replace the (empty) submodule dir with the pinned sources
            rm -rf sni
            cp -r ${sni-src} sni
            chmod -R u+w sni

            # nixpkgs protobuf is shared-only
            substituteInPlace CMakeLists.txt \
              --replace-fail "set ( Protobuf_USE_STATIC_LIBS ON )" \
                             "set ( Protobuf_USE_STATIC_LIBS OFF )"

            # nixpkgs' wxGTK is autotools-built: use FindwxWidgets (wx-config)
            # instead of vcpkg's wxWidgetsConfig.cmake
            substituteInPlace CMakeLists.txt \
              --replace-fail "find_package(wxWidgets REQUIRED CONFIG COMPONENTS core base)" \
                             "find_package(wxWidgets REQUIRED COMPONENTS core base)"

            # Load gRPC (and thereby protobuf's own CMake config) before the
            # module-mode Protobuf lookup, to avoid duplicate-target errors
            substituteInPlace CMakeLists.txt \
              --replace-fail "find_package(Protobuf REQUIRED)" \
                             "find_package(gRPC CONFIG REQUIRED)
            find_package(Protobuf REQUIRED)"
          '';

          # CMakeLists.txt has no install() rules
          installPhase = ''
            runHook preInstall
            install -Dm755 send_file manage_files -t $out/bin
            install -Dm644 snfm_config_example.yaml snfm_user_manual.md \
              -t $out/share/doc/snfm
            runHook postInstall
          '';

          meta = {
            description = "Super Nintendo file manager and ROM launcher for SNI";
            homepage = "https://github.com/zig-for/snfm";
            license = lib.licenses.mit;
            mainProgram = "manage_files";
            platforms = lib.platforms.linux;
          };
        };
      in
      {
        packages = {
          inherit snfm;
          default = snfm;
        };

        apps = {
          default = flake-utils.lib.mkApp { drv = snfm; name = "manage_files"; };
          send_file = flake-utils.lib.mkApp { drv = snfm; name = "send_file"; };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ snfm ];
          packages = [ pkgs.gdb ];
        };
      });
}
