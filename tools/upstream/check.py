#!/usr/bin/env python3
"""Read-only upstream inventory. Never imports recipes or executes downloaded code."""
import argparse
import concurrent.futures
import datetime as dt
import html
import http.client
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import threading
import time
import urllib.error
import urllib.parse as url
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
NUMERIC = r"[0-9]+(?:\.[0-9]+)*"
MAX_BYTES = 12 * 1024 * 1024
# Flat, official archive directories only. Unknown hosts require reviewed overrides.
DIRECTORY_HOSTS = {
    'ftpmirror.gnu.org', 'ftp.gnu.org', 'download.savannah.gnu.org',
    'download.savannah.nongnu.org', 'www.x.org', 'xorg.freedesktop.org',
    'downloads.xiph.org', 'www.gnupg.org', 'gstreamer.freedesktop.org',
    'download.drobilla.net', 'www.spice-space.org', 'sourceware.org',
    'www.cairographics.org', 'download.samba.org', 'www.samba.org',
    'netfilter.org', 'www.netfilter.org', 'download.libvirt.org',
    'www.tcpdump.org', 'dbus.freedesktop.org', 'www.alsa-project.org',
    'zlib.net', 'www.qemu.org', 'download.qemu.org', 'curl.se',
    'ffmpeg.org', 'nginx.org', 'www.memcached.org', 'busybox.net',
    'mesa.freedesktop.org', 'archive.mesa3d.org',
}


def numeric(value):
    """No guesswork about epochs, dates with suffixes, RCs or project semantics."""
    if not re.fullmatch(NUMERIC, value):
        return None
    parts = tuple(int(p) for p in value.split('.'))
    while len(parts) > 1 and parts[-1] == 0:
        parts = parts[:-1]
    return parts


def series(value):
    return tuple(int(p) for p in value.split('.')[:2])


def strings(text):
    # Discard // comments without damaging https:// inside quoted strings.
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|//[^\n]*', text)
    return [t for t in tokens if not t.startswith('//')]


def manifest(path):
    # Only the declarative fields are read. Unknown syntax fails closed.
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*',
                  lambda m: '' if m[0].startswith('//') else m[0], text)
    def field(name):
        match = re.search(r'\.' + name + r'\s*=\s*("(?:\\.|[^"\\])*")', text)
        if not match:
            raise ValueError('missing literal ' + name)
        return json.loads(match[1])
    name, version = field('name'), field('version')
    if name != path.parent.name:
        raise ValueError('directory and package name differ')
    sources = [json.loads(m) for m in re.findall(r'\.url\s*=\s*("(?:\\.|[^"\\])*")', text)]
    return {'name': name, 'version': version, 'sources': sources,
            'recipe': str(path.relative_to(path.parents[2]))}


def version_pattern(value, version):
    if value.count(version) != 1:
        raise ValueError('cannot identify an unambiguous version in source name/tag')
    before, after = value.split(version)
    return re.escape(before) + '(' + NUMERIC + ')' + re.escape(after)


def infer(recipe, overrides):
    name, version = recipe['name'], recipe['version']
    if name in overrides:
        spec = overrides[name]
        if 'reason' not in spec:
            raise ValueError('override must explain its policy')
        if spec.get('kind') == 'manual':
            return spec
        if set(spec) - {'kind', 'url', 'pattern', 'project', 'reason'}:
            raise ValueError('unknown override fields')
        return spec
    if not recipe['sources']:
        return {'kind': 'manual', 'reason': 'local/meta package without upstream archive'}
    if numeric(version) is None:
        return {'kind': 'manual', 'reason': 'non-numeric/pinned version requires project-specific ordering'}
    source = url.urlsplit(recipe['sources'][0])
    host, path = source.hostname, url.unquote(source.path)
    if source.scheme not in ('https', 'http') or source.username or source.password:
        return {'kind': 'manual', 'reason': 'unsupported source URL'}
    if host == 'github.com':
        m = re.fullmatch(r'/([^/]+)/([^/]+)/(?:releases/download/([^/]+)/[^/]+|archive/(?:refs/tags/)?(.+))', path)
        if not m:
            return {'kind': 'manual', 'reason': 'GitHub URL not a versioned release/archive'}
        tag = m[3] or re.sub(r'\.(tar\.(?:gz|bz2|xz)|zip)$', '', m[4])
        # Some archive URLs append /filename; the first segment is the ref.
        tag = tag.split('/')[0]
        return {'kind': 'github', 'url': f'https://api.github.com/repos/{m[1]}/{m[2]}/releases?per_page=100',
                'pattern': version_pattern(tag, version), 'reason': 'published GitHub releases, first 100 only; tags alone are not releases'}
    if host in ('files.pythonhosted.org', 'pypi.org'):
        m = re.match(r'/packages/source/[^/]+/([^/]+)/', path)
        if not m:
            return {'kind': 'manual', 'reason': 'hashed PyPI URL does not identify project safely'}
        project = m[1]
        return {'kind': 'pypi', 'url': f'https://pypi.org/pypi/{url.quote(project, safe="")}/json',
                'reason': 'non-yanked numeric releases with a source distribution'}
    if host == 'download.gnome.org':
        m = re.match(r'/sources/([^/]+)/', path)
        if m:
            return {'kind': 'gnome', 'url': f'https://download.gnome.org/sources/{m[1]}/cache.json',
                    'project': m[1], 'reason': 'GNOME numeric releases in current series only (major for GNOME 40+, otherwise major.minor)'}
    if name == 'linux' and host in ('www.kernel.org', 'cdn.kernel.org', 'kernel.org'):
        return {'kind': 'kernel', 'url': 'https://www.kernel.org/releases.json',
                'reason': 'stable/non-EOL kernel.org releases; series changes require review'}
    if host in DIRECTORY_HOSTS:
        directory, filename = path.rsplit('/', 1)
        if version in directory:
            return {'kind': 'manual', 'reason': 'version-specific directory needs explicit release index'}
        if not re.search(r'\.(tar\.(gz|xz|bz2|zst|lz)|tgz|zip)$', filename):
            return {'kind': 'manual', 'reason': 'unknown archive filename'}
        # GNU mirror redirects may change host; use the canonical archive directly.
        base = 'https://ftp.gnu.org/gnu' + directory if host == 'ftpmirror.gnu.org' else 'https://' + host + directory
        return {'kind': 'directory', 'url': base + '/',
                'pattern': version_pattern(filename, version),
                'reason': 'numeric archive filenames in this directory only; not a stability guarantee'}
    return {'kind': 'manual', 'reason': 'no reviewed upstream adapter for ' + str(host)}


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            href = dict(attrs).get('href')
            if href:
                self.links.append(href)


def candidates(spec, payload, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    kind = spec['kind']
    result = []
    if kind == 'directory':
        parser = Links(); parser.feed(payload)
        for href in parser.links:
            target = url.urljoin(spec['url'], href)
            # A directory link must name an archive in precisely that directory.
            if target.rsplit('/', 1)[0] != spec['url'].rstrip('/'):
                continue
            match = re.fullmatch(spec['pattern'], url.unquote(url.urlsplit(target).path.rsplit('/', 1)[-1]))
            if match:
                result.append((match[1], target))
        return result
    data = json.loads(payload)
    if kind == 'github':
        if not isinstance(data, list):
            raise ValueError('expected GitHub release list')
        for release in data:
            stamp = release.get('published_at')
            if release.get('draft') or release.get('prerelease') or not stamp:
                continue
            if dt.datetime.fromisoformat(stamp.replace('Z', '+00:00')) > now:
                continue
            match = re.fullmatch(spec['pattern'], release.get('tag_name', ''))
            if match:
                result.append((match[1], release['html_url']))
    elif kind == 'pypi':
        for version, files in data['releases'].items():
            if numeric(version) and any(f.get('packagetype') == 'sdist' and not f.get('yanked', False) for f in files):
                result.append((version, 'https://pypi.org/project/' + url.quote(data['info']['name'], safe='') + '/' + version + '/'))
    elif kind == 'gnome':
        if data[0] != 4:
            raise ValueError('unknown GNOME cache format')
        for version, files in data[1][spec['project']].items():
            archive = next((files[k] for k in ('tar.xz', 'tar.gz', 'tar.bz2') if k in files), None)
            if archive and numeric(version):
                result.append((version, url.urljoin(spec['url'], archive)))
    elif kind == 'kernel':
        for release in data['releases']:
            if release.get('moniker') in ('stable', 'longterm') and not release.get('iseol') and numeric(release['version']):
                result.append((release['version'], release['source']))
    else:
        raise ValueError('unknown adapter: ' + kind)
    return result


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        validate_url(newurl)
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        # Never forward a GitHub token to redirects (including another GitHub path).
        if new:
            new.remove_header('Authorization')
        return new


def validate_url(value):
    parsed = url.urlsplit(value)
    if parsed.scheme != 'https' or parsed.username or parsed.password or parsed.port not in (443, None):
        raise ValueError('upstream index must use credential-free HTTPS')
    # No arbitrary recipe-controlled URLs: infer only constructs known endpoints;
    # reviewed overrides must use one of these public hostnames as well.
    allowed = DIRECTORY_HOSTS | {'api.github.com', 'pypi.org', 'download.gnome.org', 'www.kernel.org'}
    if parsed.hostname not in allowed:
        raise ValueError('upstream host not allowlisted: ' + str(parsed.hostname))


class Fetcher:
    def __init__(self, timeout=8):
        self.timeout = timeout
        self.lock = threading.Lock()
        self.host_next = {}
        self.failed_hosts = set()
    def get(self, address):
        validate_url(address)
        host = url.urlsplit(address).hostname
        with self.lock:
            if host in self.failed_hosts:
                raise ValueError('host rate limited earlier in this run')
            delay = max(0, self.host_next.get(host, 0) - time.monotonic())
            self.host_next[host] = time.monotonic() + delay + 0.3
        time.sleep(delay)
        headers = {'User-Agent': 'joe-linux-upstream-check/1.0', 'Accept': 'application/json' if host == 'api.github.com' else '*/*'}
        token = os.environ.get('GITHUB_TOKEN')
        if host == 'api.github.com' and token:
            headers['Authorization'] = 'Bearer ' + token
        request = urllib.request.Request(address, headers=headers)
        opener = urllib.request.build_opener(SafeRedirect())
        try:
            with opener.open(request, timeout=self.timeout) as response:
                payload = response.read(MAX_BYTES + 1)
                if len(payload) > MAX_BYTES:
                    raise ValueError('upstream metadata exceeds response size limit')
                return payload.decode('utf-8')
        except urllib.error.HTTPError as exc:
            if exc.code in (403, 429):
                with self.lock:
                    self.failed_hosts.add(host)
            raise ValueError('HTTP ' + str(exc.code)) from None


def compare(recipe, spec, payload):
    found = [(v, link) for v, link in candidates(spec, payload) if numeric(v) is not None]
    current = recipe['version']
    if spec['kind'] == 'gnome':
        width = 1 if int(current.split('.')[0]) >= 40 else 2
        found = [(v, link) for v, link in found if tuple(v.split('.')[:width]) == tuple(current.split('.')[:width])]
    if not found:
        return {'status': 'unknown', 'reason': 'no comparable release in checked index'}
    newer = [(v, link) for v, link in found if numeric(v) > numeric(current)]
    if not newer:
        # Absence of a newer version from a bounded feed isn't proof of currency.
        return {'status': 'no-newer-observed', 'reason': spec['reason']}
    latest, link = max(newer, key=lambda pair: numeric(pair[0]))
    same = [(v, link) for v, link in newer if series(v) == series(current)]
    result = {'status': 'review', 'candidate': latest, 'upstream': link,
              'reason': 'new upstream version requires recipe/build/compatibility review'}
    if same:
        result['same_series_candidate'], result['same_series_upstream'] = max(same, key=lambda pair: numeric(pair[0]))
    return result


def inventory(root, overrides):
    rows = []
    paths = sorted((root / 'packages').glob('*/package.zon'))
    if not paths:
        raise ValueError('no package recipes found')
    stale = set(overrides) - {p.parent.name for p in paths}
    if stale:
        raise ValueError('overrides without recipes: ' + ', '.join(sorted(stale)))
    for path in paths:
        row = {'name': path.parent.name, 'recipe': str(path.relative_to(root)), 'sources': []}
        try:
            row = manifest(path)
            row['tracking'] = infer(row, overrides)
            if row['tracking']['kind'] != 'manual':
                if numeric(row['version']) is None:
                    raise ValueError('adapter needs numeric current version')
                validate_url(row['tracking']['url'])
                if 'pattern' in row['tracking']:
                    re.compile(row['tracking']['pattern'])
            row['status'] = 'manual' if row['tracking']['kind'] == 'manual' else 'not-checked'
            row['reason'] = row['tracking']['reason']
        except (ValueError, KeyError, TypeError, re.error) as exc:
            # Still count broken manifests in the inventory.
            row.update(status='manual', reason=str(exc))
        rows.append(row)
    return rows


def check(rows, fetcher, workers=4, progress=None, budget=15 * 60):
    # Fetch once per index; consume promptly rather than retaining every response.
    grouped = {}
    for row in rows:
        if row['status'] == 'not-checked':
            grouped.setdefault(row['tracking']['url'], []).append(row)
    deadline = time.monotonic() + budget
    def fetch(address):
        if time.monotonic() >= deadline:
            return None, 'run network budget exhausted', 'not-checked'
        try:
            return fetcher.get(address), None, None
        except (ValueError, OSError, UnicodeError, urllib.error.URLError, http.client.HTTPException) as exc:
            return None, str(exc)[:200], 'error'
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        tasks = {pool.submit(fetch, address): address for address in grouped}
        completed = 0
        for future in concurrent.futures.as_completed(tasks):
            body, error, state = future.result()
            for row in grouped[tasks.pop(future)]:
                if error:
                    row.update(status=state, reason=error)
                    continue
                try:
                    row.update(compare(row, row['tracking'], body))
                except (ValueError, KeyError, TypeError, IndexError, AttributeError) as exc:
                    row.update(status='error', reason='invalid upstream metadata: ' + str(exc)[:200])
            completed += 1
            if progress and completed % 50 == 0:
                progress(rows)
    return rows


def escape(value):
    return html.escape(str(value)).replace('|', '&#124;').replace('\n', ' ')


def report(rows, out):
    out.mkdir(parents=True, exist_ok=True)
    counts = {state: sum(r['status'] == state for r in rows) for state in sorted({r['status'] for r in rows})}
    data = {'generated_at': dt.datetime.now(dt.timezone.utc).isoformat(),
            'commit': os.environ.get('GITHUB_SHA'), 'counts': counts, 'packages': rows}
    (out / 'report.json').write_text(json.dumps(data, indent=2) + '\n')
    lines = ['# Upstream package report', '', f'Inventoried **{len(rows)} recipes**.', '',
             'Read-only candidates, not tested upgrades. Only the first source of each recipe is checked; all source URLs are inventoried in JSON. Auxiliary archives/patches, compatibility and signatures require maintainer review.', '',
             'Every recipe is accounted for. `manual`, `unknown`, `error` and `not-checked` are coverage gaps, **not** up-to-date packages. `no-newer-observed` is limited to the documented feed/series, not a guarantee.', '',
             ' | '.join(f'{k}: {v}' for k, v in counts.items()), '',
             '| Package | Installed recipe | Candidate | Same-series candidate | Status / reason |',
             '| --- | --- | --- | --- | --- |']
    for row in rows:
        lines.append('| ' + ' | '.join(escape(v) for v in (row['name'], row.get('version', '?'), row.get('candidate', ''), row.get('same_series_candidate', ''), row['status'] + ': ' + row['reason'])) + ' |')
    (out / 'report.md').write_text('\n'.join(lines) + '\n')
    summary = lines[:9] + ['', 'Download the `upstream-report` artifact for the complete Markdown/JSON inventory and upstream evidence URLs.', '', '## Candidates (first 100)', '']
    summary += [f"- **{escape(r['name'])}**: {escape(r['version'])} → {escape(r['candidate'])}" for r in rows if r['status'] == 'review'][:100]
    (out / 'summary.md').write_text('\n'.join(summary) + '\n')
    print(json.dumps(counts, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=Path('upstream-report'))
    parser.add_argument('--inventory-only', action='store_true')
    parser.add_argument('--packages', nargs='+', help='optional live smoke-test subset; reports only these recipes')
    parser.add_argument('--workers', type=int, choices=range(1, 9), default=4)
    args = parser.parse_args()
    overrides = json.loads((args.root / 'tools/upstream/overrides.json').read_text())
    rows = inventory(args.root, overrides)
    if args.packages:
        missing = set(args.packages) - {r['name'] for r in rows}
        if missing:
            parser.error('unknown packages: ' + ', '.join(sorted(missing)))
        rows = [r for r in rows if r['name'] in args.packages]
    report(rows, args.output)  # Keep a complete inventory even if network work is interrupted.
    if not args.inventory_only:
        check(rows, Fetcher(), args.workers, progress=lambda rows: report(rows, args.output))
    report(rows, args.output)
    # Failed metadata requests are visible as a failing run, but reports survive.
    return 1 if any(r['status'] == 'error' or (not args.inventory_only and r['status'] == 'not-checked') for r in rows) else 0


if __name__ == '__main__':
    raise SystemExit(main())
