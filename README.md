# Amir

Configurable multi-agent orchestration system. Amir reads a YAML team configuration, wires agents, roles, and workflow gates, and exposes a service layer for coordinating multi-agent workflows.

> **Status:** Alpha — Core architecture is established. APIs and configuration schemas may evolve.

## Prerequisites

- Python 3.13 or higher

## Quick Start

Clone and install locally:

```bash
git clone https://github.com/salimnamvar/amir.git
cd amir
pip install -e .
```

Run the CLI:

```bash
amir
```

## Development

Clone the repository and install with dev dependencies:

```bash
git clone https://github.com/salimnamvar/amir.git
cd amir
pip install -e ".[dev]"
```

Run the linter:

```bash
ruff check src/ tests/
```

Run the formatter:

```bash
ruff format src/ tests/
```

Run the type checker:

```bash
pyright
```

Run the tests:

```bash
pytest
```

## Design Principles

- Domain-driven modeling with immutable entities and value objects
- Protocol-based repository contracts
- YAML-driven configuration validated at startup with Pydantic
- Structured logging with async queue support
- Separation between contract, repository, service, and infrastructure layers

## Contributing

Contributions are accepted. Open an issue or submit a pull request at the [source repository](https://github.com/salimnamvar/amir).

## License

[Apache-2.0](LICENSE)
