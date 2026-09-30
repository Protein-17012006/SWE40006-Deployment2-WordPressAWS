"""Zips build/WordPress into build/WordPressApp.zip the way `aws deploy push --ignore-hidden-files` would on Linux:
forward-slash paths, hidden files skipped, Unix modes (755 for hook scripts, 644 for everything else).
Usage (from the repo root): python codedeploy/zip-revision.py"""
import os
import stat
import zipfile

ROOT, OUT = 'build/WordPress', 'build/WordPressApp.zip'

count = 0
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as bundle:
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if not d.startswith('.'))
        for name in sorted(filenames):
            if name.startswith('.'):
                continue
            path = os.path.join(dirpath, name)
            info = zipfile.ZipInfo(os.path.relpath(path, ROOT).replace(os.sep, '/'))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | (0o755 if name.endswith('.sh') else 0o644)) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, 'rb') as source:
                bundle.writestr(info, source.read())
            count += 1
print(f'{OUT}: {count} files, {os.path.getsize(OUT) / 1048576:.1f} MiB')
