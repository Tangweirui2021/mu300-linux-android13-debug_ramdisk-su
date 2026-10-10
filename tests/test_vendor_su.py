"""Vendor extractors must use the root path inherited from their installer parent. No real adb runs."""
import importlib.util
import os
import subprocess
import unittest
from pathlib import Path
from unittest import mock

from helpers import TOP


def load_extractor(name, su):
    spec = importlib.util.spec_from_file_location(name, TOP / 'android-vendor' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(os.environ, {'MU300_SU': su}), \
            mock.patch('tempfile.mkdtemp', return_value=str(TOP / 'work' / 'unused-mock-temp')):
        spec.loader.exec_module(module)
    return module


class VendorSu(unittest.TestCase):
    def test_vendor_archive_uses_selected_root_for_create_and_cleanup(self):
        for inherited, expected in (('/debug_ramdisk/su', '/debug_ramdisk/su'), ('', 'su')):
            with self.subTest(su=inherited):
                module = load_extractor('extract_subset', inherited)
                result = subprocess.CompletedProcess([], 0)
                with mock.patch.object(module.subprocess, 'run', return_value=result) as run:
                    self.assertIs(module.pull_vendor_archive(Path('mock-vendor.tar')), result)
                commands = [call.args[0] for call in run.call_args_list]
                self.assertEqual(len(commands), 3)
                self.assertEqual(commands[0][:2], ['adb', 'shell'])
                self.assertTrue(commands[0][2].startswith(expected + " -c 'tar -chf "))
                self.assertEqual(commands[1], ['adb', 'pull', '/data/local/tmp/mu300-subset.tar', 'mock-vendor.tar'])
                self.assertEqual(commands[2], ['adb', 'shell', expected + " -c 'rm -f /data/local/tmp/mu300-subset.tar'"])
                self.assertTrue(all(call.kwargs['stdin'] == subprocess.DEVNULL for call in run.call_args_list))

    def test_gpu_metadata_uses_selected_root(self):
        module = load_extractor('pull_closure', '/debug_ramdisk/su')
        result = subprocess.CompletedProcess([], 0, stdout=b'/vendor/lib64/a.so\r\n__RC0\r\n')
        with mock.patch.object(module, 'run', return_value=result) as run:
            self.assertEqual(module.adb('readlink -f /vendor/lib64/a.so'), b'/vendor/lib64/a.so\n')
        self.assertEqual(run.call_args.args[0], ['adb', 'exec-out',
                         "/debug_ramdisk/su -c 'readlink -f /vendor/lib64/a.so; echo __RC$?'"])

    def test_gpu_binary_pull_and_cleanup_use_selected_root(self):
        module = load_extractor('pull_closure', '/debug_ramdisk/su')
        binary = b'\x7fELF\n\x00\r\n'
        work = mock.Mock()
        work.exists.return_value = False
        work.is_file.return_value = True
        work.read_bytes.return_value = binary
        result = subprocess.CompletedProcess([], 0)
        with mock.patch.object(module, 'WORK', work), mock.patch.object(module, 'run', return_value=result) as run:
            self.assertEqual(module.adb_pull_file('/vendor/lib64/a.so'), binary)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ['adb', 'shell',
                         "/debug_ramdisk/su -c 'cat /vendor/lib64/a.so > /data/local/tmp/mu300-pull.bin'"])
        self.assertEqual(commands[1][:3], ['adb', 'pull', '/data/local/tmp/mu300-pull.bin'])
        self.assertEqual(commands[2], ['adb', 'shell',
                         "/debug_ramdisk/su -c 'rm -f /data/local/tmp/mu300-pull.bin'"])

    def test_shell_archive_consumes_inherited_root(self):
        source = (TOP / 'android-vendor/extract-subset.sh').read_text(encoding='utf-8')
        self.assertIn('SU=${MU300_SU:-su}', source)
        self.assertNotIn('adb shell "su -c', source)


if __name__ == '__main__':
    unittest.main()
