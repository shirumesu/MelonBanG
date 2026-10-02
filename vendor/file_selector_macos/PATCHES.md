# Native file type filtering

Upstream: file_selector_macos 0.9.5+1 from pub.dev, maintained in
https://github.com/flutter/packages/tree/main/packages/file_selector/file_selector_macos.
The BSD license and author notices are retained. Only runtime sources and native
package metadata are included; examples and test tooling are omitted.

The macOS implementation requires macOS 13, matching the application's target,
and uses `NSSavePanel.allowedContentTypes` for extension, UTI and MIME filters.
The unused legacy `allowedFileTypes` branch and its test override are removed,
eliminating the macOS 12 deprecation warning without hiding compiler diagnostics.
The Dart API and Windows implementation remain unchanged. Remove this override
when an upstream release removes the deprecated branch.
