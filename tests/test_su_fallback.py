"""Local variants: root discovery and source-update isolation. All adb calls inside tests are stubs.

Normally run under the available host shells. MU300_SU_TEST_ADB_SERIAL optionally runs the same
in-memory shell harness through Android's sh; it creates no files and never runs the installers.
"""
import os
import subprocess
import unittest

from helpers import TOP, shells


class SuFallback(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runners = shells()
        serial = os.environ.get('MU300_SU_TEST_ADB_SERIAL')
        if serial:
            cls.runners.append(['adb', '-s', serial, 'shell', '-T', '/system/bin/sh'])
        cls.helper = (TOP / 'tools/su-fallback.sh').read_text(encoding='utf-8')

    def run_case(self, working='/debug_ramdisk/su', boot_after=0, root_after=0,
                 output='0', status=0, attempts=4, expected=True, ticks=0):
        if not self.runners:
            self.skipTest('no working POSIX shell; set MU300_SU_TEST_ADB_SERIAL to test with Android sh')
        # Parameters below are test constants, not device/user input. State changes happen in sleep,
        # since adb runs inside a command substitution and cannot modify the parent's variables.
        code = self.helper + r'''
set -eu
tick=0
sleep() { tick=$((tick + 1)); }
adb() {
    if [ "$*" = 'shell getprop sys.boot_completed' ]; then
        if [ "$tick" -ge "$boot_after" ]; then printf '1\r\n'; else echo 0; fi
        return 0
    fi
    if [ "$*" = "shell $working -c 'id -u'" ] && [ "$tick" -ge "$root_after" ]; then
        printf '%s\r\n' "$root_output"
        return "$root_status"
    fi
    echo 'su: inaccessible or not found'
    return 1
}
'''
        code += '\n'.join([
            f"working='{working}'", f'boot_after={boot_after}', f'root_after={root_after}',
            f"root_output='{output}'", f'root_status={status}', "SU='/stale/su'",
            "MU300_SU='/stale/su'; export MU300_SU",
            f"if wait_android_root {attempts} 0 ''; then result=yes; else result=no; fi",
            'child_su=$(sh -c \'printf %s "$MU300_SU"\')',
            'printf "%s|%s|%s|%s\\n" "$result" "$SU" "$tick" "$child_su"',
        ]) + '\n'
        want = f'{"yes" if expected else "no"}|{working if expected else ""}|{ticks}|{working if expected else ""}'
        for runner in self.runners:
            with self.subTest(shell=runner):
                argv = runner if runner[0] == 'adb' else runner + ['-s']
                result = subprocess.run(argv, input=code.encode(), capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
                self.assertEqual(result.stdout.decode().replace('\r', '').strip(), want)

    def test_supported_paths(self):
        for path in ('su', '/debug_ramdisk/su', '/sbin/su', '/system/xbin/su', '/system/bin/su'):
            with self.subTest(path=path):
                self.run_case(working=path)

    def test_late_boot_and_root(self):
        self.run_case(boot_after=1, root_after=2, ticks=2)

    def test_boot_gates_ready_root(self):
        self.run_case(boot_after=2, root_after=0, ticks=2)

    def test_unfinished_boot(self):
        self.run_case(boot_after=99, expected=False, ticks=3)

    def test_missing_root(self):
        self.run_case(root_after=99, expected=False, ticks=3)

    def test_non_root_and_noisy_output(self):
        for output in ('1000', 'ok', 'uid=0(root)', '0\n0'):
            with self.subTest(output=output):
                self.run_case(output=output, expected=False, ticks=3)

    def test_failed_transport_cannot_claim_root(self):
        self.run_case(status=1, expected=False, ticks=3)

    def test_variants_use_readiness_gate(self):
        variants = list(TOP.glob('*-su-fallback.sh')) + list((TOP / 'tools').glob('*-su-fallback.sh'))
        self.assertEqual(len(variants), 8)
        for path in variants:
            with self.subTest(path=path.name):
                source = path.read_text(encoding='utf-8')
                self.assertIn('. "$TOP/tools/su-fallback.sh"', source)
                self.assertIn('wait_android_root', source)
                self.assertNotIn("-c 'echo ok'", source)

    def test_source_update_is_disabled(self):
        source = (TOP / 'install-su-fallback.sh').read_text(encoding='utf-8')
        self.assertNotIn('tools/self-update.sh', source)
        self.assertNotIn('self_update "$0"', source)


if __name__ == '__main__':
    unittest.main()
