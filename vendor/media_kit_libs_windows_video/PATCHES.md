# Local native patches

Upstream: media_kit_libs_windows_video 1.0.11 from pub.dev, MIT license (see LICENSE).
The example application and test-only development dependencies are omitted.

## libmpv

The upstream package pins media-kit's libmpv build of 2023-09-24 (mpv 652a1dd),
whose `hwdec_d3d11egl` looks for `EGL_EXT_device_query` among the display
extensions. The bundled ANGLE lists it only as a client extension, so the
zero-copy interop never loaded and every frame took `d3d11va-copy`: downloaded to
system memory and uploaded again, about 32 ms per 4K frame. mpv fixed the check
upstream on 2026-07-31.

The package now downloads mpv's own Windows build (shinchiro's mpv-winbuild-cmake,
linked from mpv.io) from the SourceForge folder that keeps every weekly release.
`hwdec-current` reads `d3d11va` and a 4K frame renders in about 1 ms. A new archive
removes the libraries extracted from the previous one, since extraction otherwise
runs only into an empty directory. To update, pick an `mpv-dev-x86_64-*.7z` from
https://sourceforge.net/projects/mpv-player-windows/files/libmpv/, set its name and
MD5, and confirm `hwdec-current` and super-resolution playback.
