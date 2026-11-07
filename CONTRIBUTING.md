# Contributing to mac-memory-warning

Thank you for considering contributing! Here are guidelines to get started.

## Development Setup

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/<your-username>/mac-memory-warning.git
   cd mac-memory-warning
   ```

2. Create a virtual environment and install development dependencies:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -e ".[dev]"
   ```

3. Run the test suite:
   ```bash
   pytest
   ```

## Pull Request Guidelines

- Ensure tests pass on macOS.
- Keep changes focused and self-contained.
- Document any new CLI arguments or configuration options in `README.md`.
