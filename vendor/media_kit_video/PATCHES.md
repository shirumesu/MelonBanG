# Local Windows disposal patch

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
