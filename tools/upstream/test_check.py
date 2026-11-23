import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('check', Path(__file__).with_name('check.py'))
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)


def recipe(source, version='1.2.3', name='example'):
    return {'name': name, 'version': version, 'sources': [source] if source else []}


class CheckerTests(unittest.TestCase):
    def test_numeric_order_not_lexicographic(self):
        self.assertGreater(c.numeric('1.10'), c.numeric('1.9'))
        self.assertEqual(c.numeric('1.0.0'), c.numeric('1'))
        for s in ['v1.2', '1.2-rc1', '1.2beta', '2026f', '1.2+local', 'abc123']:
            self.assertIsNone(c.numeric(s))

    def test_comments_urls_and_escapes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'packages' / 'example' / 'package.zon'
            path.parent.mkdir(parents=True)
            path.write_text('// .version = "9"\n.{ .name = "example", .version = "1.2",\n.description="quote\\\" //not-comment", .sources=.{ .{.url="https://github.com/u/r/archive/v1.2.tar.gz"}}, }')
            actual = c.manifest(path)
            self.assertEqual(actual['version'], '1.2')
            self.assertEqual(actual['sources'], ['https://github.com/u/r/archive/v1.2.tar.gz'])

    def test_github_release_and_archive_patterns(self):
        for tail in ['releases/download/proj-1.2.3/proj.tar.gz', 'archive/refs/tags/proj-1.2.3.tar.gz', 'archive/proj-1.2.3/name.tar.gz']:
            spec = c.infer(recipe('https://github.com/owner/repo/' + tail), {})
            self.assertEqual(spec['kind'], 'github')
            self.assertEqual(spec['pattern'], r'proj\-([0-9]+(?:\.[0-9]+)*)')
        spec = c.infer(recipe('https://github.com/o/r/archive/012abcdef.tar.gz', version='012abcdef'), {})
        self.assertEqual(spec['kind'], 'manual')

    def test_github_skips_prerelease_draft_future_and_wrong_tag(self):
        spec = c.infer(recipe('https://github.com/o/r/releases/download/v1.2.3/r.tar.gz'), {})
        releases = [dict(tag_name='v1.2.4', draft=False, prerelease=False, published_at='2020-01-01T00:00:00Z', html_url='https://github.com/o/r/releases/tag/v1.2.4')]
        for change in [{'draft': True}, {'prerelease': True}, {'published_at': '2099-01-01T00:00:00Z'}, {'tag_name': 'unrelated-9.0'}, {'tag_name': 'v1.3.0-rc1'}]:
            releases.append(dict(releases[0], **change))
        self.assertEqual(len(c.candidates(spec, json.dumps(releases))), 1)

    def test_pypi_identity_from_source_not_distro_name(self):
        spec = c.infer(recipe('https://files.pythonhosted.org/packages/source/M/Mako/mako-1.2.3.tar.gz', name='python-mako'), {})
        self.assertEqual(spec['url'], 'https://pypi.org/pypi/Mako/json')
        self.assertEqual(c.infer(recipe('https://files.pythonhosted.org/packages/ab/cd/a.tar.gz'), {})['kind'], 'manual')
        body = {'info': {'name': 'Mako'}, 'releases': {'1.2.4': [{'packagetype': 'sdist', 'yanked': False}], '2.0': [{'packagetype': 'sdist', 'yanked': True}], '3.0': [{'packagetype': 'bdist_wheel'}], '4.0rc1': [{'packagetype': 'sdist'}]}}
        self.assertEqual([v for v, _ in c.candidates(spec, json.dumps(body))], ['1.2.4'])

    def test_directory_strict_prefix_and_location(self):
        spec = c.infer(recipe('https://ftp.gnu.org/gnu/example/example-1.2.3.tar.xz'), {})
        body = '<a href="example-1.2.4.tar.xz">yes</a><a href="other-9.tar.xz">no</a><a href="example-9rc1.tar.xz">no</a><a href="https://evil.test/example-9.tar.xz">no</a><a href="../example-8.tar.xz">no</a>'
        self.assertEqual([v for v, _ in c.candidates(spec, body)], ['1.2.4'])
        self.assertEqual(c.infer(recipe('https://ftp.gnu.org/gnu/example/1.2.3/example-1.2.3.tar.gz'), {})['kind'], 'manual')

    def test_gnome_filters_to_current_series(self):
        r = recipe('https://download.gnome.org/sources/foo/1.2/foo-1.2.3.tar.xz')
        spec = c.infer(r, {})
        body = [4, {'foo': {'1.2.4': {'tar.xz': '1.2/foo-1.2.4.tar.xz'}, '1.3.0': {'tar.xz': '1.3/foo-1.3.0.tar.xz'}, '1.2.5rc1': {'tar.xz': '1.2/a.tar.xz'}}}]
        self.assertEqual(c.compare(r, spec, json.dumps(body))['candidate'], '1.2.4')

    def test_kernel_skips_rc_and_eol(self):
        r = recipe('https://www.kernel.org/pub/linux/kernel/v7.x/linux-7.3.1.tar.xz', version='7.3.1', name='linux')
        spec = c.infer(r, {})
        body = {'releases': [{'moniker': 'stable', 'version': '7.3.5', 'iseol': False, 'source': 'https://kernel.org/a'}, {'moniker': 'mainline', 'version': '7.4-rc3'}, {'moniker': 'stable', 'version': '8.0', 'iseol': True}]}
        self.assertEqual(c.compare(r, spec, json.dumps(body))['candidate'], '7.3.5')

    def test_no_release_is_unknown_not_current(self):
        r = recipe('https://github.com/o/r/archive/v1.2.3.tar.gz')
        spec = c.infer(r, {})
        self.assertEqual(c.compare(r, spec, '[]')['status'], 'unknown')

    def test_major_update_and_same_series_both_shown(self):
        r = recipe('https://ftp.gnu.org/gnu/a/a-1.2.3.tar.gz')
        spec = c.infer(r, {})
        result = c.compare(r, spec, '<a href="a-2.0.tar.gz">2</a><a href="a-1.2.4.tar.gz">1</a>')
        self.assertEqual(result['candidate'], '2.0')
        self.assertEqual(result['same_series_candidate'], '1.2.4')
        self.assertEqual(result['status'], 'review')

    def test_unknown_host_and_local_packages_manual(self):
        for r in [recipe('https://not-reviewed.example/foo.tar.gz'), recipe(None)]:
            self.assertEqual(c.infer(r, {})['kind'], 'manual')

    def test_reject_unsafe_urls(self):
        for u in ['http://pypi.org/a', 'https://127.0.0.1/a', 'https://pypi.org@evil.test/a', 'https://api.github.com:8888/a', 'https://secret@api.github.com/a']:
            with self.assertRaises(ValueError): c.validate_url(u)

    def test_redirect_drops_auth(self):
        import urllib.request
        request = urllib.request.Request('https://api.github.com/a', headers={'Authorization': 'Bearer sentinel'})
        new = c.SafeRedirect().redirect_request(request, None, 301, '', {}, 'https://api.github.com/b')
        self.assertFalse(new.has_header('Authorization'))
        with self.assertRaises(ValueError):
            c.SafeRedirect().redirect_request(request, None, 301, '', {}, 'https://evil.test/')

    def test_shared_lookup_deduplicated_and_errors_visible(self):
        class Fake:
            calls = []
            def get(self, address):
                self.calls.append(address)
                raise ValueError('HTTP 429')
        fake = Fake()
        rows = [{'name': n, 'version': '1', 'status': 'not-checked', 'tracking': {'kind': 'github', 'url': 'https://api.github.com/repos/o/r/releases'}} for n in ['a', 'b']]
        c.check(rows, fake)
        self.assertEqual(len(fake.calls), 1)
        self.assertTrue(all(r['status'] == 'error' for r in rows))

    def test_catalog_accounting(self):
        overrides = json.loads((c.ROOT / 'tools/upstream/overrides.json').read_text())
        rows = c.inventory(c.ROOT, overrides)
        self.assertEqual(len(rows), len(list((c.ROOT / 'packages').glob('*/package.zon'))))
        self.assertEqual(len({r['name'] for r in rows}), len(rows))
        self.assertTrue(all(r.get('reason') for r in rows))
        self.assertTrue(all(r['status'] in ('manual', 'not-checked') for r in rows))

    def test_inference_failure_preserves_recipe(self):
        rows = c.inventory(c.ROOT, {})
        r = next(r for r in rows if r['name'] == 'expat')
        self.assertEqual(r['status'], 'manual')
        self.assertTrue(r['sources'])
        self.assertIn('version', r)

    def test_malformed_response_is_isolated(self):
        class Fake:
            def get(self, address): return '[null]'
        row = dict(recipe('https://github.com/o/r/archive/v1.2.3.tar.gz'), status='not-checked')
        row['tracking'] = c.infer(row, {})
        c.check([row], Fake())
        self.assertEqual(row['status'], 'error')

    def test_network_budget_preserves_unchecked_rows(self):
        class Fake:
            def get(self, address): raise AssertionError('must not request')
        row = dict(recipe('https://github.com/o/r/archive/v1.2.3.tar.gz'), status='not-checked')
        row['tracking'] = c.infer(row, {})
        c.check([row], Fake(), budget=0)
        self.assertEqual(row['status'], 'not-checked')
        self.assertIn('budget', row['reason'])

    def test_gnome_modern_major_series(self):
        r = recipe('https://download.gnome.org/sources/gnome-shell/51/gnome-shell-51.1.tar.xz', version='51.1')
        spec = c.infer(r, {})
        body = [4, {'gnome-shell': {'51.2': {'tar.xz': '51/gnome-shell-51.2.tar.xz'}, '52.0': {'tar.xz': '52/gnome-shell-52.0.tar.xz'}}}]
        self.assertEqual(c.compare(r, spec, json.dumps(body))['candidate'], '51.2')

    def test_real_catalog_special_cases(self):
        overrides = json.loads((c.ROOT / 'tools/upstream/overrides.json').read_text())
        rows = {r['name']: r for r in c.inventory(c.ROOT, overrides)}
        for name in ['rust', 'libchewing', 'firefox', 'tzdata', 'newsflash', 'spirv-cross', 'spirv-headers', 'spirv-tools', 'vulkan-headers', 'vulkan-icd-loader']:
            self.assertEqual(rows[name]['status'], 'manual', name)
            self.assertTrue(rows[name]['sources'], name)
        self.assertEqual(rows['gtk4']['tracking']['project'], 'gtk')
        self.assertGreater(len(rows['rust']['sources']), 1)
        self.assertEqual(len(rows['libchewing']['sources']), 2)

    def test_stale_overrides_fail(self):
        with self.assertRaises(ValueError): c.inventory(c.ROOT, {'not-a-real-package': {'kind': 'manual', 'reason': 'test'}})

    def test_report_escapes_markdown_and_includes_all(self):
        with tempfile.TemporaryDirectory() as tmp:
            rows = [{'name': '<script>|bad', 'version': '1', 'status': 'manual', 'reason': 'x\ny', 'sources': []}]
            c.report(rows, Path(tmp))
            text = (Path(tmp) / 'report.md').read_text()
            self.assertNotIn('<script>', text)
            self.assertIn('&#124;', text)
            self.assertEqual(len(json.loads((Path(tmp) / 'report.json').read_text())['packages']), 1)


if __name__ == '__main__':
    unittest.main()
