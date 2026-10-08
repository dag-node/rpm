# SPDX-License-Identifier: MIT
"""Holds select-releases.py to its retention rule: a floor per project, the latest patch of every
series, a `<set>/` tag as its own series, and an unparsable tag ignored."""
import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "select-releases.py"
spec = importlib.util.spec_from_file_location("select_releases", SCRIPT)
select_releases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(select_releases)


class SelectTest(unittest.TestCase):
    def test_the_latest_patch_of_every_series_at_or_above_the_floor(self):
        tags = ["v0.6.2", "v0.6.1", "v0.11.1", "v0.12.0", "v0.12.3", "v0.12.1", "v1.0.0", "docs-only", "v1.0"]
        self.assertEqual(select_releases.select(tags, (0, 11, 1)), ["v1.0.0", "v0.12.3", "v0.11.1"])

    def test_no_floor_keeps_every_series(self):
        self.assertEqual(select_releases.select(["v0.1.0", "v0.1.1"], (0, 0, 0)), ["v0.1.1"])

    def test_a_set_tag_is_its_own_series_and_is_printed_as_listed(self):
        tags = ["core/v0.1.0", "core/v0.1.1", "core/v0.2.0", "acme/v0.1.0", "v0.1.0"]
        self.assertEqual(select_releases.select(tags, (0, 0, 0)),
                         ["v0.1.0", "acme/v0.1.0", "core/v0.2.0", "core/v0.1.1"])

    def test_a_floor_applies_to_every_series_of_the_project(self):
        self.assertEqual(select_releases.select(["core/v0.1.0", "v1.0.0"], (0, 11, 1)), ["v1.0.0"])

    def test_the_floor_is_a_bare_version(self):
        self.assertEqual(select_releases.parse("core/v0.1.0"), ("core", (0, 1, 0)))
        self.assertEqual(select_releases.parse("0.11.1"), ("", (0, 11, 1)))
        self.assertIsNone(select_releases.parse("Core/v0.1.0"))
        self.assertIsNone(select_releases.parse("v0.1"))


if __name__ == "__main__":
    unittest.main()
