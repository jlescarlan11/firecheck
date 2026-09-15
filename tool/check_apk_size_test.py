"""Exercise the release size gate with small synthetic APK archives."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).with_name('check_apk_size.py')


class ApkSizeGateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def apk(self, name, abis, compression=zipfile.ZIP_STORED):
        path = self.root / name
        with zipfile.ZipFile(path, 'w', compression=compression) as archive:
            archive.writestr('AndroidManifest.xml', b'manifest')
            for abi in abis:
                archive.writestr(f'lib/{abi}/libapp.so', b'code' * 100)
        return path

    def run_gate(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)],
                              capture_output=True, text=True)

    def test_single_architecture_reports_actual_file_size_and_savings(self):
        baseline = self.apk('old.apk', ['arm64-v8a', 'x86_64'])
        current = self.apk('new.apk', ['arm64-v8a'])
        report = self.root / 'report.json'
        result = self.run_gate(current, '--baseline', baseline, '--report', report)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(report.read_text())[0]
        self.assertEqual(data['bytes'], current.stat().st_size)
        self.assertGreater(data['reduction_percent'], 0)
        self.assertEqual(len(data['sha256']), 64)

    def test_universal_is_rejected_even_below_budget(self):
        apk = self.apk('universal.apk', ['arm64-v8a', 'armeabi-v7a'])
        self.assertEqual(self.run_gate(apk).returncode, 1)
        self.assertEqual(self.run_gate(apk, '--allow-universal').returncode, 0)

    def test_oversize_single_architecture_is_rejected(self):
        apk = self.apk('large.apk', ['arm64-v8a'])
        self.assertEqual(self.run_gate(apk, '--max-mb', '0.0001').returncode, 1)

    def test_compressed_native_libraries_violate_storage_policy(self):
        apk = self.apk('compressed.apk', ['arm64-v8a'], zipfile.ZIP_DEFLATED)
        result = self.run_gate(apk)
        self.assertEqual(result.returncode, 1)
        self.assertIn('compressed native libraries', result.stdout)

    def test_archive_without_native_code_is_rejected(self):
        self.assertEqual(self.run_gate(self.apk('empty.apk', [])).returncode, 1)


if __name__ == '__main__':
    unittest.main()
