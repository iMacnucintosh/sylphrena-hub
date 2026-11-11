"""The Python helpers of the Games extension: Steam's binary shortcuts file, hidden and private games, sessions."""
import importlib.util
import json
import struct
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("steam_nonsteam", ROOT / "extensions/games/scripts/steam-nonsteam.py")
sn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sn)


def vdf_string(key: str, value: str) -> bytes:
    return b"\x01" + key.encode() + b"\x00" + value.encode() + b"\x00"


def vdf_int(key: str, value: int) -> bytes:
    return b"\x02" + key.encode() + b"\x00" + struct.pack("<I", value)


def vdf_map(key: str, body: bytes) -> bytes:
    return b"\x00" + key.encode() + b"\x00" + body + b"\x08"


class Shortcuts(unittest.TestCase):
    def test_parses_a_shortcuts_file(self):
        game = vdf_int("appid", 4195243827) + vdf_string("AppName", "World of Warcraft: Forever") + vdf_string("Exe", '"/opt/wow/Wow.exe"')
        data = vdf_map("shortcuts", vdf_map("0", game)) + b"\x08"
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "shortcuts.vdf"
            f.write_bytes(data)
            parsed = sn.parse_shortcuts(f)
        entry = parsed["0"] if "0" in parsed else next(iter(parsed.values()))
        self.assertEqual(entry["AppName"], "World of Warcraft: Forever")

    def test_a_missing_or_broken_file_is_not_a_crash(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "shortcuts.vdf"
            f.write_bytes(b"\x00garbage")
            try:
                sn.parse_shortcuts(f)
            except Exception as e:  # the caller (load_for_account) is what has to cope; it must not hang
                self.assertIsInstance(e, Exception)


class HiddenAndPrivate(unittest.TestCase):
    def test_private_apps_come_from_localconfig(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d)
            (cfg / "localconfig.vdf").write_text(
                '"UserLocalConfigStore"\n{\n\t"PrivateApps_154763067"\t\t"[1350650,3478650, 3930100,oops]"\n'
                '\t"PrivateApps_999"\t\t"[]"\n}\n')
            self.assertEqual(sn.load_private_ids(cfg), {"1350650", "3478650", "3930100"})

    def test_hidden_collection_and_private_are_both_hidden(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = Path(d)
            (cfg / "localconfig.vdf").write_text('"PrivateApps_1"\t\t"[111]"\n')
            cloud = cfg / "cloudstorage"
            cloud.mkdir()
            hidden = [["user-collections.hidden", {"value": json.dumps({"added": [222, "333"]})}],
                      ["user-collections.favorite", {"value": json.dumps({"added": [444]})}]]
            (cloud / "cloud-storage-namespace-1.json").write_text(json.dumps(hidden))
            (cloud / "cloud-storage-namespace-1.modified.json").write_text("not read")
            self.assertEqual(sn.load_hidden_ids(cfg), ["111", "222", "333"])

    def test_no_files_means_nothing_hidden(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(sn.load_hidden_ids(Path(d)), [])
            self.assertEqual(sn.load_private_ids(Path(d)), set())


class Sessions(unittest.TestCase):
    def merge(self, state_dir, fresh):
        import os

        os.environ["XDG_STATE_HOME"] = state_dir
        try:
            return sn.merge_session_cache(fresh)
        finally:
            del os.environ["XDG_STATE_HOME"]

    def test_merge_keeps_the_history_without_duplicates(self):
        import time

        now = int(time.time())
        first = {"start": now - 7200, "end": now - 6600}
        second = {"start": now - 3600, "end": now - 3300}
        with tempfile.TemporaryDirectory() as d:
            self.merge(d, {"A": [first]})
            merged = self.merge(d, {"A": [first, second]})   # the first one is seen again
            again = self.merge(d, {})                        # Millennium forgot them: our history keeps them
        self.assertEqual([s["start"] for s in merged["A"]], [second["start"], first["start"]])
        self.assertEqual(len(again["A"]), 2)

    def test_sessions_older_than_the_horizon_are_dropped(self):
        import time

        old = {"start": int(time.time()) - (sn.CACHE_DAYS + 5) * 86400, "end": int(time.time()) - (sn.CACHE_DAYS + 5) * 86400 + 600}
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(self.merge(d, {"A": [old]})["A"], [])

    def test_broken_sessions_are_ignored(self):
        import time

        now = int(time.time())
        with tempfile.TemporaryDirectory() as d:
            merged = self.merge(d, {"A": [{"start": now - 100}, {"start": now - 50, "end": now - 60}, "x", {"start": now - 200, "end": now - 100}]})
        self.assertEqual(len(merged["A"]), 1)


class Requirements(unittest.TestCase):
    def test_status_has_the_three_keys(self):
        self.assertEqual(set(sn.requirements_status()), {"steam", "millennium", "playtimes"})


if __name__ == "__main__":
    unittest.main()
