# LocalMCP Xcode Security Settings

Approved by the user on 3 October 2026. Xcode 27.0 (27A266a); canonical project configuration: `xcode/project.yml`.

## Enabled settings

- `ENABLE_HARDENED_RUNTIME = YES`: retained existing protection.
- `ENABLE_APP_SANDBOX = YES`: retained on application targets.
- `ENABLE_ENHANCED_SECURITY = YES`: inherited project-wide, including the static core library.
- `ENABLE_POINTER_AUTHENTICATION = YES`: verified Xcode cascade on LocalMCP, M3MCPBridge and M3MCPCore. Release architectures are `arm64 x86_64 arm64e`; no prebuilt third-party dependency prevents this.
- `ENABLE_SECURITY_COMPILER_WARNINGS = YES`: verified Xcode cascade; compiler checks apply to the languages actually compiled.
- `ONLY_ACTIVE_ARCH = NO`: retained so distributed binaries include every configured architecture.
- `com.apple.security.hardened-process = true` and `enhanced-security-version-string = 2`: LocalMCP, M3MCPBridge and SandboxTransportProbe.
- `com.apple.security.hardened-process.hardened-heap = true`: runtime allocation isolation.
- `com.apple.security.hardened-process.dyld-ro = true`: read-only dyld state.
- `com.apple.security.hardened-process.platform-restrictions-string = 2`: additional runtime platform restrictions.

The probe shares the app entitlement file. M3MCPCore is a static library and receives no process entitlements. Existing sandbox data permissions and Keychain access groups were preserved.

## Not enabled

- Hardware Memory Tagging and its soft-mode/pure-data/tagged-receive options: not part of this macOS rollout.
- `ENABLE_HARDWARE_CHECKED_POINTER_ARITHMETIC_SLICE` and its overflow entitlement: the skill's supported iOS/watchOS hardware path does not apply to this macOS project.
- C bounds safety, C++ bounds-safe buffers, additional C/Objective-C analyzer and clang-tidy settings: no such source languages detected in the app, core and bridge; no blanket unrelated warning changes.

## Deferred

- Real Keychain, personal data provider and Apple Events acceptance with the hardened signed app. These are required before publishing a replacement release.
- Instruments measurements for UI responsiveness under large responses. Observation behavior is tested; numerical performance gains have not been measured.
- Migration away from deprecated `kSecUseAuthenticationUIFail`: requires native tests preserving noninteractive startup and deliberately interactive access.

## Verification

Full Swift suite with ThreadSanitizer: 408 tests, four opt-in calendar skips, zero failures and no sanitizer race reports. Unsigned Universal Release, signed main app and signed transport fixture builds pass. Strict deep signatures pass. Physical-Mac transport checks accept the valid embedded bridge and reject a wrong token and a foreign executable. Signed main-app start/restart and bridge authentication pass with isolated synthetic credentials. These tests do not establish real Keychain continuity, data-source permissions or Apple approval.

Detailed evidence and remaining release gates are retained in `xcode-security-audit-plan.md`.
