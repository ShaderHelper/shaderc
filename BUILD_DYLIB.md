Build macOS universal dylib
==========================

This repository can be built as a macOS universal dynamic library (dylib) containing both x86_64 and arm64 slices.

Usage
-----

From the repository root run:

```bash
./build_dylib_universal.sh
```

Options (via environment variables):
- BUILD_TYPE: Debug|Release (default Release)
- ARCHS: space-separated architectures (default "arm64 x86_64")
- JOBS: parallel build jobs (defaults to logical CPU count)

What the script does
- Configures two out-of-tree builds (one per arch) with CMake using CMAKE_OSX_ARCHITECTURES
- Builds the project for each arch
- Finds the built shaderc dylibs and uses `lipo` to create a universal dylib at `build-universal/lib/libshaderc_shared.dylib`

Verification
------------

You can inspect the produced file with:

```bash
file build-universal/lib/libshaderc_shared.dylib
lipo -info build-universal/lib/libshaderc_shared.dylib
otool -L build-universal/lib/libshaderc_shared.dylib
```

Notes
-----
- The script disables building tests and examples to speed up build.
- If you prefer an XCFramework instead of a lipo'd dylib, consider building frameworks per-arch and running `xcodebuild -create-xcframework`.
