"""CLI entry point — command-line interface for amir."""

from __future__ import annotations

from pathlib import Path
import sys

from amir.infrastructure.bootstrap import Amir


def main() -> int:
    """Main entry point."""
    config_path = Path("team-config.yaml")
    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        return 1

    app = Amir.from_config_path(config_path)
    app.start()

    try:
        if app.service is None:
            print("Service not initialized", file=sys.stderr)
            return 1

        agents = app.service.list_agents()
        gates = app.service.list_gates_in_order()

        print(f"Team: {config_path.stem}")
        print(f"Agents: {len(agents)}")
        for agent in agents:
            print(f"  {agent.name}: {', '.join(agent.roles)}")

        print(f"Gates: {len(gates)}")
        for gate in gates:
            print(f"  {gate.name}: {gate.from_role} -> {gate.to_role}")

        return 0
    finally:
        app.stop()


if __name__ == "__main__":
    sys.exit(main())
