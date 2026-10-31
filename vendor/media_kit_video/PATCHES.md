# Local native patches

## Windows disposal

Upstream: media_kit_video 2.0.1 from pub.dev, MIT license (see LICENSE).
The upstream example application is omitted; runtime source is retained.

The Windows method channel previously acknowledged VideoOutputManager.Dispose
before its detached worker unregistered the Flutter texture. Closing the window
after awaiting Player.dispose could then destroy the engine while native texture
callbacks were still running, causing an access violation in flutter_windows.dll.

The app also uses normal window close after disposal. On Windows,
window_manager.destroy posts WM_QUIT directly; that bypassed the runner's normal
WM_DESTROY sequence and independently caused a shutdown access violation in the
packaged application. Awaiting disposal alone did not fix that failure.

The local patch changes three Windows source files: Dispose accepts a completion
callback; the worker waits for texture destruction and its render-thread queue;
the plugin sends the method result on the platform thread only after completion.
The UI thread remains available for texture-unregistration callbacks throughout.

Keep this override until an upstream release provides equivalent completion
semantics. Revalidate by closing the packaged application during active playback,
checking exit code zero and absence of child processes.

## Hot restart (Windows and macOS)

Debug startup awaits `VideoOutputManager.Reset` before `MediaKit.ensureInitialized`.
Flutter retains the native plugin across hot restart, while media_kit 1.2.6 sends
`quit` to old mpv handles whose Dart NativeCallable callbacks have been destroyed;
mpv's core thread then calls the dead wakeup callback from `mp_shutdown_clients`
and the process crashes (EXC_BAD_ACCESS in `append_event` on macOS).
Reset clears those wakeup callbacks and releases all old video outputs before
replying on the platform thread. Windows also unregisters the textures and drains
the render queue before replying; macOS replies after every output has freed its
render context and unregistered its texture (see "macOS disposal"). Every player in this app has a
VideoController, so the manager owns all affected handles. This also prevents old
video outputs from accumulating across restarts. Keep this ordering if player
initialization changes; audio-only players would need their own handle cleanup.

Related upstream callback fix: https://github.com/media-kit/media-kit/pull/1416.

## macOS texture visibility

The macOS `TextureHW`, `TextureSW`, and `SafeResizableTexture` classes are internal
implementation details. Keep them internal so Swift does not export their
`Unmanaged<CVPixelBuffer>` methods into the framework's Objective-C header, where
Swift 6.4 emits an invalid `__unsafe_unretained` qualifier for the Core Video pointer.
Flutter still calls them through `FlutterTexture`; retain the protocol conformance
and `Unmanaged.passRetained` ownership behavior. The plugin registration remains
public. This patch is macOS-only; the upstream common and iOS copies are unchanged.
Revalidate native video playback, seeking, resizing, and disposal after upgrades.

The macOS podspec also leaves `$(inherited)` unquoted in
`GCC_PREPROCESSOR_DEFINITIONS`. Quoting the expansion combines CocoaPods' debug
macros into one `POD_CONFIGURATION_DEBUG` definition and triggers redefinition
warnings in Swift's Clang importer. Keep the inherited macros as separate tokens.

## macOS disposal

media_kit destroys the mpv handle five seconds after `Player.dispose`, and mpv
aborts in `mp_clients_destroy` ("mpv_render_context_free() not called") when a
render context still exists. `VideoOutputManager.Dispose` only dropped the
manager's reference: the render context was freed in `TextureHW.deinit`, which
waits for Flutter's texture registry and for render jobs that captured the
output. Before the fix, three of four Command-Q quits during playback crashed
on 2026-10-26 (macOS 27, Apple M4; shutdown took about six seconds). Dispose
now queues on the worker the release of the render context and the
unregistration of the texture, and replies on the main thread after both; five
quits afterwards, two during playback, left no crash report. Reset disposes
every output the same way before replying; two hot restarts during playback
kept the app running and playback worked again afterwards. Revalidate by quitting with
Command-Q during playback and checking that no new crash report appears.

## macOS render scheduling

Same purpose as "Windows render scheduling". Each mpv update queued its own
render on the worker; with 4K and the quality super-resolution chain on an M4,
mpv sent about 73 updates per 10 s while about 42 renders of 240 ms finished,
so the queue grew by about three jobs per second, each pushing the current frame
through the whole chain again. `VideoOutput.updateCallback` now queues one
render that serves every update before it starts. `render` calls
`mpv_render_context_update` with the CGL context current and draws, takes a
buffer and calls `textureFrameAvailable` only for a new frame or after new pixel
buffers. Measured afterwards: 51–70 updates per 10 s merged into 43–47 renders of
212 ms; GPU-bound playback itself is unchanged. `setSize` also queues that
render: the output was resized only on mpv's next update, which a paused
player does not send, so toggling super-resolution or leaving fullscreen while
paused kept the old size until playback resumed.

Not ported: the Windows two-texture rotation; `SwappableObjectManager` already
rotates three IOSurface buffers, so Flutter reads a finished one. The per-frame
`DispatchQueue.main.sync` for `textureFrameAvailable` stays, since it measured
0.1–3 ms. `mpv_render_context_render` blocks until the frame's target time
(`MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME` defaults to on), so its wall time,
about 41 ms at 24 fps, is not GPU time. Revalidate playback, pausing, seeking,
resizing and super-resolution toggling after upgrades.

## macOS Swift Package Manager

The macOS sources use the upstream Swift package layout and explicit Apple
framework and `Mpv` imports. Existing Windows disposal and macOS texture
visibility patches are preserved. The podspec points to the same source tree.

The package depends on Flutter's generated `FlutterFramework` package and the
local `media_kit_libs_macos_video` package's real `Mpv` binary product. This
application always ships video libraries, so the Swift package requires them
instead of silently compiling the upstream no-video stub. Native frameworks
are downloaded and embedded by Swift Package Manager using the libraries
package's checksum-pinned upstream artifacts.

The Swift compiler passes the same `GL_SILENCE_DEPRECATION` and
`COREVIDEO_SILENCE_GL_DEPRECATION` macros to its Clang importer as CocoaPods.
These silence only the intentional OpenGL/Core Video API deprecations while
preserving other compiler warnings.

## Fixed output size

`NativeVideoController` resized the output to the video's own dimensions on
every `videoParams` change, even after `setSize` had fixed a size, while its
`width`/`height` fields kept naming the fixed one; a later `setSize` with the
same values then returned early and the output stayed at the video size. The
patch skips the automatic resize while a fixed size is set. MelonBanG fixes the
output to the displayed size only while super-resolution shaders are enabled,
so they have room to upscale, and clears it otherwise. Revalidate the output
size after switching files of different dimensions with the setting on.

## Windows texture resize

`VideoOutput::Resize` assigned the new texture ID before storing its descriptor,
and recreated the ANGLE surface without the textures lock. Flutter's raster
thread keeps calling the previous texture's callback until it frees it, and that
callback looked up the current ID with `unordered_map::at`; in the gap it threw
`std::out_of_range` and the process aborted (0xc0000409 in flutter_windows.dll,
seen in two crash dumps while toggling super-resolution, which resizes the output
on every toggle and display change). The callbacks now use `find` and return
null when the ID is not stored, the ID is set under the lock after the descriptor
is stored, and the surface is recreated under the same lock so `Read` never copies
from a surface being replaced.

## Windows super-resolution switch

Turning super-resolution on resizes the output, and the first frame at the new
size compiles the shader chain, which ANGLE translates for Direct3D: seconds for
the larger chains. `Resize` registered the new texture before that frame, so the
video was black throughout. Now the recreated surface replaces the shown texture
only after `Render` has drawn into it; until then Flutter keeps the previous
texture's surface and its last frame (the first texture is still registered at
once, since Dart waits for its ID). The render thread is single, so the picture
stays on that frame while the chain compiles; the app points
`gpu-shader-cache-dir` at its own folder, since mpv finds no cache folder with
libmpv's `config=no`, so later switches load the compiled shaders.

The replaced texture stays registered until Dart reports, after the frame that
shows the new one, `VideoOutputManager.TextureShown`: Dart switches a frame or
two after the new ID arrives, and an unregistered texture draws nothing, so
unregistering it at once flashed black. Disposal unregisters the retired
textures before the current one.

`VideoOutputManager.SetSize` now replies once a frame is drawn at the size,
forcing that render, so a paused player applies the size too; the Dart
`setSize` no longer skips an unchanged size. The app sets the shaders, then
awaits `setSize`, and announces the switch when it completes. macOS replies
the same way (`redrawNext` forces the render; without a video size, and on
disposal, it replies at once). It needs no texture change: its texture keeps
the same ID, and Flutter shows the last pixel buffer until
`textureFrameAvailable`. Revalidate turning super-resolution on, off and
between chains while playing and paused, and resizing the window with it on,
on both platforms.

## Windows render scheduling

mpv notifies a render for every frame and also without one, and a render with
super-resolution can outlast the notifications. Each notification queued its own
render, so a slow chain built a backlog that redrew the current frame through the
whole shader chain. `NotifyRender` now queues one render that serves every
notification before it starts, and `NeedsRender` skips a render, and the texture
frame notification, unless `mpv_render_context_update` reports a new frame or the
surface was recreated. The update runs with the context current, since it can load
the hardware decoding interop.

`ANGLESurfaceManager` draws into two internal textures in turn. `Read`, called on
Flutter's raster thread, copies the last finished one, and the mutex covers only
that copy and the swap, so the raster thread no longer waits for a render: a 42 ms
4K super-resolution render had held Flutter, and the comments above the video, to
about 45 frames per second. Revalidate playback, pausing, seeking, resizing and
super-resolution toggling after upgrades.
