"""Real listener regression; Blender callbacks alone are stubbed, not socket I/O."""

import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import threading
import time
import traceback
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
ADDON_PATH = None


class SocketModule:
    def __init__(self, factory=socket.socket, hide_exclusive=False):
        self.socket = factory
        self.hide_exclusive = hide_exclusive

    def __getattr__(self, name):
        if self.hide_exclusive and name == "SO_EXCLUSIVEADDRUSE":
            raise AttributeError(name)
        return getattr(socket, name)


def load_server_class(path, socket_module=socket, os_module=os, threading_module=threading):
    tree = ast.parse(path.read_bytes(), filename=str(path))
    server = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "BlenderMCPServer")
    namespace = {
        "__name__": "futsal_listener_regression",
        "bpy": SimpleNamespace(app=SimpleNamespace(background=False, timers=Mock())),
        "socket": socket_module, "os": os_module, "threading": threading_module, "queue": queue,
        "json": json, "time": time, "traceback": traceback,
        "_register_edit_capture_handlers": lambda: None,
        "_unregister_edit_capture_handlers": lambda: None,
        "get_edit_recorder": lambda: SimpleNamespace(drain=lambda: None),
    }
    exec(compile(ast.Module(body=[server], type_ignores=[]), str(path), "exec"), namespace)
    return namespace["BlenderMCPServer"]


class BlenderListenerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        local = json.loads((ROOT / "tools" / "mcp" / "local.json").read_text(encoding="utf-8-sig"))
        cls.addon_path = ADDON_PATH or Path(local["addonPath"])
        print(
            f"On-disk listener: {cls.addon_path}; "
            f"sha256={hashlib.sha256(cls.addon_path.read_bytes()).hexdigest()}",
            flush=True,
        )

    def make_server(self, socket_module=socket, os_module=os, port=0):
        owned_threads = []

        def make_thread(*args, **kwargs):
            thread = threading.Thread(*args, **kwargs)
            owned_threads.append(thread)
            return thread

        threads = SimpleNamespace(Thread=make_thread, Lock=threading.Lock)
        server_type = load_server_class(self.addon_path, socket_module, os_module, threads)
        server = server_type(host="127.0.0.1", port=port)

        def stop_and_join():
            listener = server.socket
            try:
                server.stop()
            finally:
                for thread in owned_threads:
                    if thread.ident is not None:
                        thread.join(timeout=5)
                self.assertTrue(all(not thread.is_alive() for thread in owned_threads), "Owned listener threads did not stop.")
                self.assertIsNone(server.socket)
                if listener is not None:
                    self.assertEqual(listener.fileno(), -1)

        self.addCleanup(stop_and_join)
        return server

    @unittest.skipUnless(os.name == "nt", "Exercises actual Windows concurrent binding semantics.")
    def test_overlapping_starts_admit_exactly_one_listener(self):
        barrier = threading.Barrier(3, timeout=10)
        self.addCleanup(barrier.abort)
        bind_results = queue.Queue()

        class GatedSocket(socket.socket):
            def bind(self, address):
                barrier.wait()
                try:
                    result = super().bind(address)
                except OSError as error:
                    bind_results.put((threading.get_ident(), self, error))
                    raise
                bind_results.put((threading.get_ident(), self, None))
                return result

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as reservation:
            reservation.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            reservation.bind(("127.0.0.1", 0))
            endpoint = reservation.getsockname()
            servers = [self.make_server(SocketModule(GatedSocket), port=endpoint[1]) for _ in range(2)]
            starters = [threading.Thread(target=server.start) for server in servers]
            for starter in starters:
                starter.start()
        try:
            barrier.wait()
        except BaseException:
            barrier.abort()
            raise
        finally:
            for starter in starters:
                starter.join(timeout=10)
        self.assertTrue(all(not starter.is_alive() for starter in starters), "Startup threads did not finish.")
        winners = [server for server in servers if server.running]
        self.assertEqual(
            len(winners), 1,
            f"Concurrent real start() calls admitted {len(winners)} listeners at {endpoint}; expected exactly one.",
        )
        winner = winners[0]
        loser = next(server for server in servers if server is not winner)
        self.assertEqual(bind_results.qsize(), 2)
        attempts = {}
        for _ in starters:
            thread_id, listener, error = bind_results.get_nowait()
            attempts[thread_id] = (listener, error)
        self.assertEqual(set(attempts), {starter.ident for starter in starters})
        winning_socket, winning_error = attempts[starters[servers.index(winner)].ident]
        losing_socket, losing_error = attempts[starters[servers.index(loser)].ident]
        self.assertIs(winning_socket, winner.socket)
        self.assertIsNone(winning_error)
        self.assertIsInstance(losing_error, OSError)
        self.assertIn(losing_error.winerror, (10048, 10013))
        self.assertEqual(losing_socket.fileno(), -1)
        self.assertIsNone(loser.socket)
        self.assertEqual(winner.socket.getsockname(), endpoint)
        self.assertEqual(winner.socket.getsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE), 1)
        self.assertEqual(winner.socket.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR), 0)
        for sequence in range(2):
            command = {"type": "futsal_listener_probe", "params": {"sequence": sequence}}
            with socket.create_connection(endpoint, timeout=5) as client:
                client.sendall(json.dumps(command).encode())
                received, accepted = winner.command_queue.get(timeout=5)
                self.assertEqual(received, command)
                self.assertEqual(accepted.getsockname(), endpoint)
                self.assertEqual(accepted.getpeername(), client.getsockname())
                with winner._clients_lock:
                    self.assertIn(accepted, winner._clients)
            self.assertTrue(loser.command_queue.empty())

    @unittest.skipUnless(os.name == "nt", "Exercises actual Windows SO_REUSEADDR competition.")
    def test_actual_listener_rejects_reuseaddr_competitor(self):
        server = self.make_server()
        server.start()
        self.assertTrue(server.running)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as competitor:
            competitor.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            with self.assertRaises(OSError):
                competitor.bind(server.socket.getsockname())
        self.assertTrue(server.running)

    @unittest.skipUnless(os.name == "nt", "Exercises an existing Windows reuse listener without replacing it.")
    def test_existing_reuse_listener_is_not_replaced(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as existing:
            existing.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            existing.bind(("127.0.0.1", 0))
            existing.listen(1)
            existing.settimeout(5)
            endpoint = existing.getsockname()
            server = self.make_server(port=endpoint[1])
            server.start()
            self.assertFalse(server.running)
            self.assertIsNone(server.socket)
            with socket.create_connection(endpoint, timeout=5), existing.accept()[0] as accepted:
                self.assertEqual(accepted.getsockname(), endpoint)

    def test_windows_without_exclusive_option_fails_closed(self):
        server = self.make_server(SocketModule(hide_exclusive=True), SimpleNamespace(name="nt"))
        server.start()
        self.assertFalse(server.running)
        self.assertIsNone(server.socket)

    def test_non_windows_without_exclusive_option_uses_default_binding(self):
        server = self.make_server(SocketModule(hide_exclusive=True), SimpleNamespace(name="posix"))
        server.start()
        self.assertTrue(server.running)
        self.assertEqual(server.socket.getsockname()[0], "127.0.0.1")
        self.assertEqual(server.socket.getsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR), 0)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--addon-path", type=Path, help="On-disk fixture for explicit listener mutation checks.")
    args, remaining = parser.parse_known_args()
    ADDON_PATH = args.addon_path
    unittest.main(argv=[__file__, *remaining])
