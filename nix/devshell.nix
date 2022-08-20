{ mkShell, lib, stdenv

, gdb
, glxinfo
, parallel
, pkg-config
, python
, scdoc
, tracy
, vulkan-loader
, vttest
, wabt
, wasmtime
, wraptest
, zig

, bzip2
, fontconfig
, freetype
, libpng
, libGL
, libX11
, libXcursor
, libXext
, libXi
, libXinerama
, libXrandr
}:
let
  # See package.nix. Keep in sync.
  rpathLibs = [
    libpng
    libGL
  ] ++ lib.optionals stdenv.isLinux [
    libX11
    libXcursor
    libXi
    libXrandr
  ];
in mkShell rec {
  name = "ghostty";

  nativeBuildInputs = [
    # For builds
    pkg-config
    scdoc
    zig

    # Testing
    gdb
    parallel
    python
    tracy
    vttest
    wraptest

    # wasm
    wabt
    wasmtime
  ];

  buildInputs = [
    # TODO: non-linux
  ] ++ lib.optionals stdenv.isLinux [
    libpng
    libX11
    libXcursor
    libXext
    libXi
    libXinerama
    libXrandr
  ];

  # This should be set onto the rpath of the ghostty binary if you want
  # it to be "portable" across the system.
  LD_LIBRARY_PATH = lib.makeLibraryPath rpathLibs;
}
