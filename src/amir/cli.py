"""CLI entry point — command-line interface for amir."""

from __future__ import annotations

from pathlib import Path
import sys

from amir.infrastructure.bootstrap import Amir


def main() -> int:
    """Main entry point."""
    exit_code = 0
    config_path = Path("team-config.yaml")
    if not config_path.exists():
        print(f"Config not found: {config_path}", file=sys.stderr)
        exit_code = 1
    else:
        app = Amir.from_config_path(config_path)
        app.start()

        try:
            if app.service is None:
                print("Service not initialized", file=sys.stderr)
                exit_code = 1
            else:
                agents = app.service.list_agents()
                gates = app.service.list_gates_in_order()

                print(f"Team: {config_path.stem}")
                print(f"Agents: {len(agents)}")
                for agent in agents:
                    print(f"  {agent.name}: {', '.join(agent.roles)}")

                print(f"Gates: {len(gates)}")
                for gate in gates:
                    print(f"  {gate.name}: {gate.from_role} -> {gate.to_role}")
        finally:
            app.stop()
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
