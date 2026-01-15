# SocketRocket
WebSocket client library for iOS, macOS, and tvOS developed by Facebook. Provides RFC 6455 compliant WebSocket implementation with TLS support, proxy handling, and high performance.
## Project Type
Objective-C library distributed as CocoaPods pod, Carthage framework, or direct Xcode subproject integration.
## Key Technologies
- **Language:** Objective-C
- **Platforms:** iOS (6.0+), macOS (10.8+), tvOS (9.0+)
- **Frameworks:** CFNetwork, Security, CoreServices (macOS)
- **Build System:** Xcode project + Makefile for testing
- **Package Managers:** CocoaPods, Carthage
- **Dependencies:** icucore library
## Project Structure
SocketRocket/
├── SocketRocket/               # Main library source code
│   ├── SRWebSocket.h/m        # Primary WebSocket implementation
│   ├── SRSecurityPolicy.h/m   # SSL/TLS security policies
│   ├── SocketRocket.h         # Umbrella header
│   └── Internal/              # Internal implementation details
│       ├── Proxy/             # HTTP proxy support
│       ├── Security/          # SSL pinning and security
│       ├── Delegate/          # Delegate management
│       └── Utilities/         # Helper utilities
├── Tests/                     # Unit and integration tests
│   └── SRAutobahnTests.m     # Autobahn test suite integration
├── TestChat/                  # Demo iOS application
├── TestChatServer/            # Demo WebSocket server (Python/Go)
├── Configurations/            # Xcode build configurations
└── TestSupport/              # Testing infrastructure scripts
## Installation Methods
### CocoaPods
```ruby
pod 'SocketRocket'
### Carthage
github "facebook/SocketRocket"
### Manual
Drag `SocketRocket.xcodeproj` into your workspace (not recommended due to indexing overhead).
## Common Commands
### Testing
```bash
make test          # Run short test suite (scenarios 1-8)
make test_all      # Run full Autobahn test suite
make test_perf     # Run performance tests (scenario 9)
### Building
```bash
make               # Build library
make clean         # Clean build artifacts
### Xcode Testing
- Select `SocketRocket` scheme
- Run tests with `⌘+U`
### Demo Application
```bash
# Setup test environment (first time only)
make test
# Start Python test server
source .env/bin/activate
pip install git+https://github.com/tornadoweb/tornado.git
python TestChatServer/py/chatroom.py
# Or use Go server
cd TestChatServer/go
go run chatroom.go
# Run TestChat.app from Xcode
# Open browser to http://localhost:9000
## Core API
### SRWebSocket
Main WebSocket class with lifecycle methods:
- `initWithURLRequest:` - Initialize with URL
- `open` - Open connection
- `close` - Close connection
- `sendData:error:` - Send binary data
- `sendString:error:` - Send UTF-8 string
### SRWebSocketDelegate
Implement to receive WebSocket events:
- `webSocketDidOpen:`
- `webSocket:didReceiveMessageWithString:`
- `webSocket:didReceiveMessageWithData:`
- `webSocket:didFailWithError:`
- `webSocket:didCloseWithCode:reason:wasClean:`
## Key Features
- TLS/wss support with self-signed certificate handling
- SSL certificate pinning
- HTTP proxy support
- IPv4/IPv6 support
- Ping/pong frame handling
- Asynchronous, non-blocking design with background thread processing
- Autobahn test suite compliant (~300 core tests)
- Self-retaining between open and close (similar to NSURLConnection)
## Dependencies
- Ruby gems: `cocoapods`, `xcpretty` (for development)
- Python virtualenv (for testing) - set up via `TestSupport/setup_env.sh`
- Autobahn test suite (for WebSocket protocol conformance testing)
## Architecture Notes
- Main WebSocket logic in `SRWebSocket.m` (~2000+ lines)
- Internal components isolated in `Internal/` directory
- Uses background thread for network operations
- Delegate callbacks dispatched to appropriate queue
- Security policies separated for customization
- Proxy connection handling abstracted in dedicated class
## Testing
Test suite uses Autobahn WebSocket test suite for protocol conformance. Tests verify:
- Frame parsing and generation
- Handshake compliance
- UTF-8 validation
- Control frame handling
- Compression support
- Error handling
## Contributing
- Branch from `master` for new features
- Add tests for new functionality
- Update documentation for API changes
- Ensure test suite passes
- Match existing code style (lines under 140 chars)
- Complete CLA at https://code.facebook.com/cla
## License
BSD license - see LICENSE file
