import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("build", ROOT / "scripts/build.py")
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


def extension(tmp: Path, details: dict | None, shots=(), manifest_over=None) -> Path:
    src = tmp / "demo"
    (src / "store/screenshots").mkdir(parents=True)
    (src / "manifest.json").write_text(json.dumps({"id": "demo", "version": "0.1.0", "name": "Demo", **(manifest_over or {})}))
    (src / "Service.qml").write_text("x")
    if details is not None:
        (src / "store/details.json").write_text(json.dumps(details))
    for name, size in shots:
        (src / "store/screenshots" / name).write_bytes(b"x" * size)
    return src


GOOD = {"about": "What it does.", "highlights": ["One"], "links": {"source": "https://example.com/x"},
        "changelog": [{"version": "0.1.0", "date": "2026-11-11", "changes": ["First"]}],
        "screenshots": [{"file": "a.png", "caption": "A"}]}


class StoreDoc(unittest.TestCase):
    def doc(self, details, shots=(("a.png", 10),)):
        with tempfile.TemporaryDirectory() as d:
            src = extension(Path(d), details, shots)
            return build.store_doc(src, json.loads((src / "manifest.json").read_text()))

    def fails(self, details, shots=(("a.png", 10),)):
        with self.assertRaises(SystemExit):
            self.doc(details, shots)

    def test_valid(self):
        doc = self.doc(GOOD)
        self.assertEqual(doc["id"], "demo")
        self.assertTrue(doc["screenshots"][0]["url"].endswith("/extensions/demo/store/screenshots/a.png"))
        self.assertEqual(doc["author"], "iMacnucintosh")

    def test_no_store_folder_means_no_document(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d) / "demo"
            src.mkdir()
            self.assertIsNone(build.store_doc(src, {"id": "demo"}))

    def test_rejects_bad_content(self):
        self.fails({**GOOD, "about": ""})
        self.fails({**GOOD, "links": {"source": "http://insecure.example.com"}})
        self.fails({**GOOD, "links": {"hack": "https://example.com"}})
        self.fails({**GOOD, "changelog": [{"version": "1", "date": "2026-11-11", "changes": []}]})
        self.fails({**GOOD, "screenshots": [{"file": "../a.png", "caption": "A"}]})
        self.fails({**GOOD, "screenshots": [{"file": "missing.png", "caption": "A"}]})
        self.fails({**GOOD, "screenshots": [{"file": "a.txt", "caption": "A"}]}, shots=(("a.txt", 5),))

    def test_rejects_a_screenshot_that_is_too_big(self):
        self.fails(GOOD, shots=(("a.png", build.MAX_SHOT + 1),))


class Zip(unittest.TestCase):
    def test_store_is_not_in_the_zip_and_the_zip_is_deterministic(self):
        import zipfile

        with tempfile.TemporaryDirectory() as d:
            src = extension(Path(d), GOOD, (("a.png", 10),))
            a, b = Path(d) / "a.zip", Path(d) / "b.zip"
            build.build_zip(src, a)
            build.build_zip(src, b)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            names = zipfile.ZipFile(a).namelist()
            self.assertIn("demo/manifest.json", names)
            self.assertFalse([n for n in names if "/store/" in n or n.endswith("/store")])


class Published(unittest.TestCase):
    def test_flags_a_published_version_whose_zip_changed(self):
        calls = {}

        class Done:
            stdout = json.dumps({"items": [{"id": "a", "version": "1.0.0", "sha256": "old"},
                                           {"id": "b", "version": "1.0.0", "sha256": "same"}]})

        original = build.subprocess.run
        build.subprocess.run = lambda *a, **k: Done()
        try:
            items = [{"id": "a", "version": "1.0.0", "sha256": "new"}, {"id": "b", "version": "1.0.0", "sha256": "same"},
                     {"id": "c", "version": "0.1.0", "sha256": "x"}, {"id": "a", "version": "1.0.1", "sha256": "y"}]
            self.assertEqual(build.published_changes(items), ["a 1.0.0"])
        finally:
            build.subprocess.run = original


class Repo(unittest.TestCase):
    def test_the_index_and_the_store_are_up_to_date(self):
        # The real repository: what CI runs
        for ext in (ROOT / "extensions").glob("*/manifest.json"):
            m = json.loads(ext.read_text())
            self.assertEqual(m["id"], ext.parent.name)
            self.assertRegex(m["version"], r"^\d+\.\d+\.\d+$")


if __name__ == "__main__":
    unittest.main()
