#!/usr/bin/env python3
"""Read-only release-helper checks; never contact Apple or boot simulators."""
import importlib.util
import os
import struct
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch


def load_module(name):
    path = Path(__file__).with_name(f"{name}.py")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


asc = load_module("asc")
simulate = load_module("simulate")


def build(version):
    return {"attributes": {"version": version}}


class BuildNumberTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {"ASC_APP_ID": "existing-app"}, clear=True)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_highest_number_can_be_on_a_later_page(self):
        pages = [(200, {"data": [build("7"), build("9")],
                        "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?cursor=second"}}),
                 (200, {"data": [build("47"), build("2.3.1")], "links": {"next": None}})]
        with patch.object(asc, "call", side_effect=pages) as call:
            self.assertEqual(asc.next_build_number(5), 48)
            self.assertEqual(call.call_args_list[1].args[1], "/v1/builds?cursor=second")

    def test_ci_floor_can_be_above_existing_builds(self):
        with patch.object(asc, "call", return_value=(200, {"data": [build("7")]})):
            self.assertEqual(asc.next_build_number(25), 25)

    def test_explicit_duplicate_or_lower_number_is_rejected(self):
        with patch.object(asc, "call", return_value=(200, {"data": [build("7")]})):
            for value in ("7", "6", "garbage", "8.1"):
                with self.subTest(value=value), self.assertRaises(ValueError):
                    asc.next_build_number(20, value)
            self.assertEqual(asc.next_build_number(20, "8"), 8)

    def test_pagination_must_not_send_credentials_to_another_origin(self):
        with patch.object(asc, "call", return_value=(200, {"data": [], "links": {"next": "https://other.example/v1/builds"}})):
            with self.assertRaisesRegex(RuntimeError, "outside its API"):
                asc.next_build_number(5)

    def test_repeated_pagination_link_fails(self):
        path = "/v1/builds?filter[app]=existing-app&limit=200"
        with patch.object(asc, "call", return_value=(200, {"data": [], "links": {"next": path}})):
            with self.assertRaisesRegex(RuntimeError, "repeated"):
                asc.next_build_number(5)

    def test_api_error_never_guesses_a_build_number(self):
        with patch.object(asc, "call", return_value=(403, {"errors": [{"title": "Forbidden"}]})):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403"):
                asc.next_build_number(5)

    def test_sign_only_can_use_a_floor_without_store_record(self):
        with patch.dict(os.environ, {"ALLOW_MISSING_APP": "1"}, clear=True):
            self.assertEqual(asc.next_build_number(5), 5)
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(RuntimeError):
            asc.next_build_number(5)


class SimulatorTests(unittest.TestCase):
    def test_layouts_require_the_actual_family_and_all_six_combinations(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            def write(name, width, height):
                (cache / name).write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + struct.pack(">II", width, height))
            for name in simulate.expected_layout_names("ipad"):
                write(name, 1448, 1086)
            self.assertEqual(simulate.missing_layout_names("ipad", cache), [])
            self.assertEqual(len(simulate.missing_layout_names("iphone", cache)), 6)
            for name in simulate.expected_layout_names("iphone"):
                write(name, 590, 1280)
            self.assertEqual(simulate.missing_layout_names("iphone", cache), [])
            wrong = "layout-phone-modern-loop.png"
            write(wrong, 1448, 1086)
            self.assertEqual(simulate.missing_layout_names("iphone", cache), [wrong])
            (cache / wrong).write_text("not a PNG")
            self.assertEqual(simulate.missing_layout_names("iphone", cache), [wrong])

    def test_newest_available_runtime_with_both_families_is_selected(self):
        devices = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
                {"name": "iPhone 16", "udid": "old-phone"}, {"name": "iPad Air", "udid": "old-pad"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
                {"name": "iPhone 17 Pro", "udid": "phone"}, {"name": "iPad Pro (11-inch)", "udid": "pad"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                {"name": "iPhone 18", "udid": "unavailable", "isAvailable": False}, {"name": "iPad Air", "udid": "new-pad"}],
            "com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [{"name": "Apple TV", "udid": "tv"}]}}
        self.assertEqual([(family, d["udid"]) for family, d in simulate.select_devices(devices)],
                         [("iphone", "phone"), ("ipad", "pad")])

    def test_missing_one_family_is_an_error(self):
        with self.assertRaises(RuntimeError):
            simulate.select_devices({"devices": {"iOS-26": [{"name": "iPad Air", "udid": "pad"}]}})

    def test_a_missing_result_or_failure_cannot_count_as_success(self):
        self.assertIsNone(simulate.result_state("app launched"))
        self.assertEqual(simulate.result_state("self-test passed"), "passed")
        self.assertEqual(simulate.result_state("self-test passed\nSELF-TEST FAILED: later check"), "failed")


if __name__ == "__main__":
    unittest.main()
