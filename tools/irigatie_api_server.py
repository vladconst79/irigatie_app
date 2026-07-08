#!/usr/bin/env python3
import argparse
import configparser
import datetime as dt
import decimal
import json
import os
import urllib.error
import urllib.request
from urllib.parse import urlparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pymysql


DEFAULT_CONFIG = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "irigatie", "irigatie.conf")
)
DEFAULT_BIND_HOST = "127.0.0.1"
DEFAULT_BIND_PORT = 8091


class ApiConfig:
    def __init__(self, path, gateway_url=None):
        parser = configparser.ConfigParser()
        parser.read(path)
        sql = "SQL"
        gateway = "HTTP Gateway"

        self.path = path
        self.db_host = parser.get(sql, "DB_SERVER")
        self.db_port = parser.getint(sql, "DB_PORT", fallback=3306)
        self.db_user = parser.get(sql, "DB_USER")
        self.db_pass = parser.get(sql, "DB_PASS")
        self.db_name = parser.get(sql, "DB_NAME")
        self.gateway_host = parser.get(gateway, "BIND_HOST", fallback="127.0.0.1")
        self.gateway_port = parser.getint(gateway, "BIND_PORT", fallback=8080)
        self.gateway_token = parser.get(gateway, "AUTH_TOKEN", fallback="")
        self.gateway_url_override = gateway_url.rstrip("/") if gateway_url else None
        self.socket_path = parser.get(
            gateway,
            "SOCKET_PATH",
            fallback=parser.get("Control Socket", "SOCKET_PATH", fallback="N/A"),
        )

    @property
    def gateway_url(self):
        if self.gateway_url_override:
            return self.gateway_url_override
        host = self.gateway_host
        if host == "0.0.0.0":
            host = "127.0.0.1"
        return "http://%s:%d" % (host, self.gateway_port)


class SnapshotRepository:
    def __init__(self, config):
        self.config = config

    def snapshot(self):
        with self._connect() as conn:
            zones = self._fetch_zones(conn)
            schedules = self._fetch_schedules(conn)
            manual_programs = self._fetch_manual_programs(conn, zones)
            runtime = self._fetch_runtime(conn)
            last_rain = self._fetch_last_rain(conn)

        gateway = self._fetch_gateway_status()
        zones = self._apply_relay_state(zones, gateway.get("relay_zones") or {})
        if gateway.get("runtime"):
            runtime = {**runtime, **gateway["runtime"]}
        if gateway.get("queue"):
            queue = gateway["queue"]
        else:
            queue = {"pending": 0, "max": 4}

        return {
            "ok": True,
            "database": {"ok": True, "name": self.config.db_name},
            "gateway": {
                "online": bool(gateway.get("online")),
                "socket_path": self.config.socket_path,
            },
            "queue": queue,
            "runtime": runtime,
            "last_rain": last_rain,
            "zones": zones,
            "schedules": schedules,
            "manual_programs": manual_programs,
        }

    def _connect(self):
        return pymysql.connect(
            host=self.config.db_host,
            port=self.config.db_port,
            user=self.config.db_user,
            password=self.config.db_pass,
            database=self.config.db_name,
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True,
            connect_timeout=5,
            read_timeout=5,
            write_timeout=5,
        )

    def _fetch_zones(self, conn):
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, denumire AS name, tip AS type, activ AS enabled "
                "FROM trasee ORDER BY id;"
            )
            return [normalize_row(row) for row in cursor.fetchall()]

    def _fetch_schedules(self, conn):
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, traseu_id AS zone_id, mon AS month, "
                "dom AS day_of_month, dow AS day_of_week, h AS hour, "
                "m AS minute, durata AS duration_minutes, "
                "max_ploaie AS max_rain_mm, ploaie AS current_rain_mm "
                "FROM programari ORDER BY mon, dom, dow, "
                "CAST(SUBSTRING_INDEX(h, ',', 1) AS UNSIGNED), "
                "CAST(SUBSTRING_INDEX(m, ',', 1) AS UNSIGNED), id;"
            )
            return [normalize_row(row) for row in cursor.fetchall()]

    def _fetch_manual_programs(self, conn, zones):
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM progman ORDER BY id;")
            programs = []
            for row in cursor.fetchall():
                durations = {}
                for zone in zones:
                    zone_id = int(zone["id"])
                    durations[str(zone_id)] = int(row.get("durata_t%d" % zone_id) or 0)
                programs.append(
                    {
                        "id": int(row["id"]),
                        "name": row.get("denumire") or "Manual %s" % row["id"],
                        "zone_durations": durations,
                    }
                )
            return programs

    def _fetch_runtime(self, conn):
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM runtime_state WHERE id = 1;")
            row = cursor.fetchone()
            if not row:
                return {
                    "state": "unknown",
                    "source": None,
                    "command": None,
                    "program_id": None,
                    "zone_id": None,
                    "remaining_seconds": 0,
                    "heartbeat_at": None,
                    "message": "runtime_state row missing",
                }

        row = normalize_row(row)
        expected_end = row.get("expected_end_at")
        remaining = 0
        if isinstance(expected_end, str):
            try:
                end = dt.datetime.fromisoformat(expected_end)
                remaining = max(0, int((end - dt.datetime.now()).total_seconds()))
            except ValueError:
                remaining = 0

        return {
            "state": row.get("state") or "unknown",
            "source": row.get("source"),
            "command": row.get("command"),
            "program_id": row.get("program_id"),
            "zone_id": row.get("traseu_id"),
            "remaining_seconds": remaining,
            "heartbeat_at": row.get("heartbeat_at"),
            "message": row.get("message"),
        }

    def _fetch_last_rain(self, conn):
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT source, event_time, amount_mm, raw_value "
                "FROM rain_events ORDER BY event_time DESC, id DESC LIMIT 1;"
            )
            row = cursor.fetchone()
        if not row:
            return {"source": "N/A", "event_time": "N/A", "amount_mm": 0}
        return normalize_row(row)

    def _fetch_gateway_status(self):
        if not self.config.gateway_token:
            return {"online": False}

        request = urllib.request.Request(
            self.config.gateway_url + "/status",
            headers={"Authorization": "Bearer " + self.config.gateway_token},
        )
        try:
            with urllib.request.urlopen(request, timeout=1.5) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (OSError, urllib.error.URLError, json.JSONDecodeError):
            return {"online": False}

        daemon = payload.get("daemon") or {}
        runtime = daemon.get("runtime") or {}
        queue = daemon.get("queue") or {}
        return {
            "online": bool(payload.get("ok")),
            "queue": {
                "pending": queue.get("pending_watering_commands", 0),
                "max": queue.get("max_pending_watering_commands", 4),
            },
            "runtime": {
                "state": daemon.get("daemon_state") or runtime.get("state"),
                "program_id": daemon.get("current_program") or runtime.get("program_id"),
                "zone_id": daemon.get("current_zone") or runtime.get("traseu_id"),
                "remaining_seconds": daemon.get("remaining_seconds") or 0,
                "heartbeat_at": runtime.get("heartbeat_at"),
                "message": runtime.get("message"),
            },
            "relay_zones": (daemon.get("relay_state") or {}).get("zones") or {},
        }

    def _apply_relay_state(self, zones, relay_zones):
        updated = []
        for zone in zones:
            relay = relay_zones.get(str(zone["id"])) or {}
            zone = {**zone}
            zone["relay_active"] = bool(relay.get("active"))
            zone["relay_value"] = relay.get("value")
            updated.append(zone)
        return updated

    def execute_manual_program(self, program_id):
        return self._post_gateway_command("/commands/exec", {"program_id": program_id})

    def start_scheduled_program(self, program_id):
        return self._post_gateway_command("/commands/start", {"program_id": program_id})

    def _post_gateway_command(self, endpoint, payload):
        if not self.config.gateway_token:
            raise RuntimeError("HTTP gateway token is not configured")

        body = json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            self.config.gateway_url + endpoint,
            data=body,
            method="POST",
            headers={
                "Authorization": "Bearer " + self.config.gateway_token,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                response_body = response.read().decode("utf-8")
                decoded = json.loads(response_body)
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError("Gateway HTTP %d: %s" % (exc.code, detail)) from exc
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as exc:
            raise RuntimeError("Gateway command failed: %r" % exc) from exc

        if not decoded.get("ok"):
            raise RuntimeError("Gateway rejected command: %s" % decoded)

        return decoded


class ApiHandler(BaseHTTPRequestHandler):
    server_version = "IrigatieAppApi/0.1"

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_common_headers()
        self.end_headers()

    def do_GET(self):
        if self.path == "/api/snapshot":
            self.write_snapshot()
            return
        if self.path == "/health":
            self.write_json(200, {"ok": True})
            return
        self.write_json(404, {"ok": False, "error": "unknown endpoint"})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/manual/execute":
            self.write_command_response(self.server.repository.execute_manual_program)
            return
        if path == "/api/schedules/start":
            self.write_command_response(self.server.repository.start_scheduled_program)
            return
        self.write_json(404, {"ok": False, "error": "unknown endpoint"})

    def write_snapshot(self):
        try:
            payload = self.server.repository.snapshot()
            self.write_json(200, payload)
        except Exception as exc:
            self.write_json(500, {"ok": False, "error": repr(exc)})

    def write_command_response(self, command):
        try:
            body = self.read_json_body()
            program_id = body.get("program_id")
            if isinstance(program_id, bool) or not isinstance(program_id, int):
                self.write_json(400, {"ok": False, "error": "program_id must be an integer"})
                return
            if program_id <= 0:
                self.write_json(400, {"ok": False, "error": "program_id must be positive"})
                return

            gateway_response = command(program_id)
            self.write_json(
                202,
                {
                    "ok": True,
                    "program_id": program_id,
                    "gateway": gateway_response,
                },
            )
        except Exception as exc:
            self.write_json(500, {"ok": False, "error": repr(exc)})

    def read_json_body(self):
        content_length = self.headers.get("Content-Length")
        if content_length is None:
            return {}

        try:
            length = int(content_length)
        except ValueError as exc:
            raise ValueError("invalid Content-Length") from exc

        if length <= 0:
            return {}

        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def write_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_common_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_common_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Cache-Control", "no-store")

    def log_message(self, format, *args):
        return


def normalize_row(row):
    normalized = {}
    for key, value in row.items():
        if isinstance(value, dt.datetime):
            normalized[key] = value.isoformat(sep=" ", timespec="seconds")
        elif isinstance(value, decimal.Decimal):
            normalized[key] = float(value)
        else:
            normalized[key] = value
    return normalized


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument(
        "--gateway-url",
        default=os.environ.get("IRIGATIE_GATEWAY_URL"),
        help="Controller gateway base URL, for example http://192.168.19.52:8080",
    )
    parser.add_argument("--host", default=DEFAULT_BIND_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_BIND_PORT)
    args = parser.parse_args()

    config = ApiConfig(args.config, gateway_url=args.gateway_url)
    server = ThreadingHTTPServer((args.host, args.port), ApiHandler)
    server.repository = SnapshotRepository(config)
    print("Serving MariaDB API on http://%s:%d" % (args.host, args.port))
    print("Using config %s" % config.path)
    print("Using gateway %s" % config.gateway_url)
    server.serve_forever()


if __name__ == "__main__":
    main()
