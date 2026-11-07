# Contributing to Memory Warning

Thank you for considering contributing! Here are guidelines to get started.

## Development Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/<your-username>/mac-memory-warning.git
   cd mac-memory-warning
   ```

2. Edit the native Swift source in `macos/main.swift` and rebuild the application bundle:
   ```bash
   ./build_app.sh
   ```

3. Launch `Memory Warning.app` to verify your changes.

## Pull Request Guidelines

- Ensure `./build_app.sh` compiles cleanly on macOS.
- Keep changes focused and self-contained.
- Document any new features or configuration options in `README.md`.
