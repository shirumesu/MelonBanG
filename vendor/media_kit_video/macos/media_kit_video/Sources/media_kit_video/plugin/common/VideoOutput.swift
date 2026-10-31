import CoreGraphics
import Foundation

#if canImport(Flutter)
  import Flutter
#elseif canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// This class creates and manipulates the different types of FlutterTexture,
// handles resizing, rendering calls, and notify Flutter when a new frame is
// available to render.
//
// To improve the user experience, a worker is used to execute heavy tasks on a
// dedicated thread.
public class VideoOutput: NSObject {
  // Will be called on the main thread
  public typealias TextureUpdateCallback = (Int64, CGSize) -> Void

  private static let isSimulator: Bool = {
    let isSim: Bool
    #if targetEnvironment(simulator)
      isSim = true
    #else
      isSim = false
    #endif
    return isSim
  }()

  private let handle: OpaquePointer
  private let enableHardwareAcceleration: Bool
  private let registry: FlutterTextureRegistry
  private let textureUpdateCallback: TextureUpdateCallback
  private let worker: Worker = .init()
  private var width: Int64?
  private var height: Int64?
  private var texture: ResizableTextureProtocol!
  private var textureId: Int64 = -1
  private var currentSize: CGSize = CGSize.zero
  private var disposed: Bool = false
  private let renderLock = NSLock()
  private var renderPending = false
  // MelonBanG: |setSize| callers waiting for the next drawn frame; used on
  // the worker only.
  private var drawnCallbacks: [() -> Void] = []

  init(
    handle: Int64,
    configuration: VideoOutputConfiguration,
    registry: FlutterTextureRegistry,
    textureUpdateCallback: @escaping TextureUpdateCallback
  ) {
    let handle = OpaquePointer(bitPattern: Int(handle))
    assert(handle != nil, "handle casting")

    self.handle = handle!
    width = configuration.width
    height = configuration.height
    enableHardwareAcceleration = configuration.enableHardwareAcceleration
    self.registry = registry
    self.textureUpdateCallback = textureUpdateCallback

    super.init()

    worker.enqueue {
      self._init()
    }
  }

  deinit {
    worker.cancel()

    disposed = true
    if textureId != -1 {
      disposeTextureId()
    }
  }

  // MelonBanG: mpv aborts when its handle is destroyed while a render context
  // still exists, and media_kit destroys it five seconds after disposal. The
  // worker frees the context, then the texture is unregistered and completion
  // runs on the main thread; until then queued jobs keep this output alive.
  public func dispose(_ completion: @escaping () -> Void) {
    worker.enqueue {
      self.disposed = true
      self.texture.dispose()
      self.disposeTextureId()
      // MelonBanG: no frame follows, and each caller still gets its reply.
      let callbacks = self.drawnCallbacks
      self.drawnCallbacks = []
      DispatchQueue.main.async {
        callbacks.forEach { $0() }
        completion()
      }
    }
  }

  // MelonBanG: |onDrawn| runs on the main thread once a frame is drawn with
  // this size and every option set before, such as the shaders.
  public func setSize(
    width: Int64?,
    height: Int64?,
    onDrawn: @escaping () -> Void
  ) {
    worker.enqueue {
      self.width = width
      self.height = height
      self.drawnCallbacks.append(onDrawn)
      // MelonBanG: a paused player sends no update that would draw the size.
      self.texture.redrawNext()
      self.updateCallback()
    }
  }

  private func drawn() {
    let callbacks = drawnCallbacks
    drawnCallbacks = []
    if !callbacks.isEmpty {
      DispatchQueue.main.async {
        callbacks.forEach { $0() }
      }
    }
  }

  private func _init() {
    let enableHardwareAcceleration =
      VideoOutput.isSimulator ? false : enableHardwareAcceleration

    NSLog(
      "VideoOutput: enableHardwareAcceleration: \(enableHardwareAcceleration)"
    )

    if VideoOutput.isSimulator {
      NSLog(
        "VideoOutput: warning: hardware rendering is disabled in the iOS simulator, due to an incompatibility with OpenGL ES"
      )
    }

    if enableHardwareAcceleration {
      texture = SafeResizableTexture(
        TextureHW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    } else {
      texture = SafeResizableTexture(
        TextureSW(
          handle: handle,
          // Use `weak self` to prevent memory leaks
          updateCallback: { [weak self]() in
            guard let that = self else {
              return
            }
            that.updateCallback()
          }
        )
      )
    }

    DispatchQueue.main.sync { [weak self]() in
      guard let that = self else {
        return
      }
      that.registerTextureId()
    }
  }

  // Must be run on the main thread
  private func registerTextureId() {
    // Textures must be registered on the platform thread.
    textureId = registry.register(texture)
    // textureUpdateCallback must run on the main thread
    textureUpdateCallback(textureId, CGSize(width: 0, height: 0))
  }

  private func disposeTextureId() {
    let registry_ = self.registry
    let textureId_ = self.textureId
    textureId = -1
    DispatchQueue.main.async {
      // Textures must be unregistered on the platform thread
      registry_.unregisterTexture(textureId_)
    }
  }

  // MelonBanG: one queued render serves every notification before it starts,
  // so a render slower than the notifications does not build a backlog.
  public func updateCallback() {
    renderLock.lock()
    let pending = renderPending
    renderPending = true
    renderLock.unlock()
    if pending {
      return
    }

    worker.enqueue {
      self._updateCallback()
    }
  }

  private func _updateCallback() {
    renderLock.lock()
    renderPending = false
    renderLock.unlock()

    if disposed {
      return
    }

    let size = videoSize

    if size.width == 0 || size.height == 0 {
      // MelonBanG: without a video there is nothing to wait for.
      drawn()
      return
    }

    if currentSize != size {
      currentSize = size

      texture.resize(size)
      DispatchQueue.main.sync { [weak self] in
        guard let that = self else { return }
        // textureUpdateCallback must run on the main thread
        that.textureUpdateCallback(that.textureId, size)
      }
    }

    if !texture.render(size) {
      return
    }
    DispatchQueue.main.sync { [weak self] in
      guard let that = self else { return }
      // Textures must be marked as available from the main thread
      that.registry.textureFrameAvailable(that.textureId)
    }
    drawn()
  }

    private var videoSize: CGSize {
        // fixed size
        if width != nil && height != nil {
            return CGSize(
                width: Double(width!),
                height: Double(height!)
            )
        }
        
        let params = MPVHelpers.getVideoOutParams(handle)
        return CGSize(
            width: Double(width ?? (params.rotate == 0 || params.rotate == 180
                                    ? params.dw
                                    : params.dh)),
            height: Double(height ?? (params.rotate == 0 || params.rotate == 180
                                      ? params.dh
                                      : params.dw))
        )
  }
}
