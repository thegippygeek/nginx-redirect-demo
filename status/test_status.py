#!/usr/bin/env python3
"""test_status.py — unit tests for the Phase 5 deltas to status.py.

Python 3 standard library only (matching status.py's constraint). Importing
status runs no I/O and binds no socket, so build()/read_config/_render_row can
be driven directly. Run standalone with no env set so the module defaults are
the values under test:

    python3 status/test_status.py
"""

import importlib.util
import json
import os
import tempfile
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("status", os.path.join(_HERE, "status.py"))
status = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(status)


class RepointedDefaults(unittest.TestCase):
    """The two module defaults follow the topology to the switch (Phase 5)."""

    def test_conf_path_default_is_active_proxy(self):
        # Only meaningful when DEMO_CONF_PATH is unset — the standalone default.
        if "DEMO_CONF_PATH" not in os.environ:
            self.assertEqual(status.CONF_PATH, "/etc/nginx/demo/active-proxy.conf")

    def test_proxy_probe_default_targets_the_switch(self):
        if "DEMO_PROXY_PROBE" not in os.environ:
            self.assertEqual(status.PROXY_PROBE, "http://switch:8081/nginx-health")


class RenderRowRemote(unittest.TestCase):
    """_render_row surfaces the client's real remote_addr (EV2-01)."""

    def test_remote_field_is_rendered_from_the_log_row(self):
        row = {
            "t": "2026-07-22T11:34:06+10:00",
            "path": "/whoami",
            "status": 200,
            "backend": "OLD",
            "ms": "1784684046.064",
            "bhost": "server-old",
            "remote": "172.19.0.9",
        }
        out = status._render_row(row)
        self.assertEqual(out["remote"], "172.19.0.9")

    def test_remote_defaults_to_empty_string_when_absent(self):
        out = status._render_row({"backend": "OLD"})
        self.assertEqual(out["remote"], "")


class ReadConfigSelector(unittest.TestCase):
    """read_config still parses the switch's active-proxy.conf selector."""

    def test_default_selector_read_as_upper(self):
        body = (
            "# switch/active-proxy.conf — THE ONLY FILE THE PRESENTER EDITS\n"
            "# Change `old` to `new` to cut over. Nothing else.\n"
            "map $server_port $active_backend {\n"
            "    default old;\n"
            "}\n"
        )
        with tempfile.NamedTemporaryFile("w", suffix=".conf", delete=False) as fh:
            fh.write(body)
            path = fh.name
        try:
            value, extras, err = status.read_config(path)
            self.assertIsNone(err)
            self.assertEqual(value, "OLD")
            self.assertEqual(extras, [])
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
