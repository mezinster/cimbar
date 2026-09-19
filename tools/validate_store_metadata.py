#!/usr/bin/env python3
"""Validate the F-Droid recipe and the fastlane store listings.

F-Droid builds from the committed tree at a release tag, so everything it reads
must already agree when the tag is pushed; a mistake found afterwards needs a
new release to fix. Run locally with:

    python3 tools/validate_store_metadata.py

Exits non-zero and prints every problem it found, rather than stopping at the
first one — a release checklist is more useful complete than early.
"""

import os
import re
import struct
import sys

import yaml

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_ID = "com.nfcarchiver.cimbar"
PUBSPEC = os.path.join(REPO, "app", "pubspec.yaml")
GRADLE = os.path.join(REPO, "app", "android", "app", "build.gradle")
RELEASE_WORKFLOW = os.path.join(REPO, ".github", "workflows", "release.yml")
FDROID = os.path.join(REPO, "fdroid", APP_ID + ".yml")
LISTINGS = os.path.join(REPO, "fastlane", "metadata", "android")
ARB_DIR = os.path.join(REPO, "app", "lib", "l10n")

# Limits F-Droid (and fastlane supply) enforce or truncate at.
LIMITS = {
    "title.txt": 50,
    "short_description.txt": 80,
    "full_description.txt": 4000,
}
CHANGELOG_MAX_CHARS = 500
IMAGE_SIZES = {"icon.png": (512, 512), "featureGraphic.png": (1024, 500)}

problems = []


def fail(msg):
    problems.append(msg)


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def read_pubspec_version():
    """Return (versionName, versionCode) from the committed pubspec."""
    for line in read(PUBSPEC).splitlines():
        m = re.match(r"^version:\s*(\S+)\+(\d+)\s*$", line)
        if m:
            return m.group(1), int(m.group(2))
    fail("app/pubspec.yaml has no 'version: <name>+<code>' line")
    return None, None


def check_app_id():
    gradle = read(GRADLE)
    m = re.search(r'applicationId\s*=\s*"([^"]+)"', gradle)
    if not m:
        fail("no applicationId in app/android/app/build.gradle")
    elif m.group(1) != APP_ID:
        fail("applicationId is '%s' but the F-Droid recipe is for '%s'" % (m.group(1), APP_ID))


def check_flutter_pin():
    """Replicate the recipe's prebuild: it greps FLUTTER_VERSION out of
    release.yml and `git checkout`s it in the Flutter srclib, so the value has
    to be an exact tag, not a range such as 3.44.x."""
    found = re.findall(r".*FLUTTER_VERSION: '(.*)'", read(RELEASE_WORKFLOW))
    if len(found) != 1:
        fail("release.yml must have exactly one \"FLUTTER_VERSION: '<x.y.z>'\" line, found %d" % len(found))
    elif not re.fullmatch(r"\d+\.\d+\.\d+", found[0]):
        fail("release.yml FLUTTER_VERSION '%s' is not an exact x.y.z Flutter tag" % found[0])
    else:
        print("release.yml Flutter: %s" % found[0])


def check_fdroid(version_name, version_code):
    if not os.path.isfile(FDROID):
        fail("missing F-Droid recipe %s" % os.path.relpath(FDROID, REPO))
        return
    meta = yaml.safe_load(read(FDROID))

    builds = meta.get("Builds") or []
    if not builds:
        fail("fdroid recipe has no Builds entries")
        return

    codes = [b.get("versionCode") for b in builds]
    dupes = {c for c in codes if codes.count(c) > 1}
    if dupes:
        fail("fdroid recipe has duplicate versionCode(s): %s" % sorted(dupes))

    for b in builds:
        name = b.get("versionName", "?")
        for key in ("versionName", "versionCode", "commit", "subdir", "output"):
            if not b.get(key):
                fail("fdroid build %s is missing '%s'" % (name, key))
        commit = str(b.get("commit", ""))
        # A release tag is fine for the first submission (the tag does not exist
        # before the release); pin the full sha once it does.
        if commit and not re.fullmatch(r"[0-9a-f]{40}", commit) and commit != "v%s" % name:
            fail(
                "fdroid build %s pins commit '%s' — expected a full 40-char sha or the tag 'v%s'"
                % (name, commit, name)
            )
        if b.get("subdir") and b.get("subdir") != "app":
            fail("fdroid build %s has subdir '%s', expected 'app'" % (name, b.get("subdir")))

    cur_code = meta.get("CurrentVersionCode")
    cur_name = str(meta.get("CurrentVersion"))

    # checkupdates reads the versionCode out of the committed pubspec. A
    # CurrentVersionCode ahead of it names a build that does not exist.
    if cur_code is not None and version_code is not None and cur_code > version_code:
        fail(
            "fdroid CurrentVersionCode (%s) is ahead of pubspec versionCode (%s)"
            % (cur_code, version_code)
        )
    if cur_code is not None and cur_code not in codes:
        fail(
            "fdroid CurrentVersionCode (%s) has no matching build entry (have %s)"
            % (cur_code, sorted(c for c in codes if c is not None))
        )
    if cur_code is not None and cur_name:
        match = [b for b in builds if b.get("versionCode") == cur_code]
        if match and str(match[0].get("versionName")) != cur_name:
            fail(
                "fdroid CurrentVersion '%s' disagrees with the versionCode %s build entry ('%s')"
                % (cur_name, cur_code, match[0].get("versionName"))
            )

    # Run UpdateCheckData the way checkupdates does: <file>|<code regex>|.|<name regex>.
    ucd = str(meta.get("UpdateCheckData", ""))
    parts = ucd.split("|")
    if len(parts) != 4:
        fail("fdroid UpdateCheckData '%s' is not '<file>|<code re>|.|<name re>'" % ucd)
        return
    path, code_re, _, name_re = parts
    target = os.path.join(REPO, path)
    if not os.path.isfile(target):
        fail("fdroid UpdateCheckData names '%s', which does not exist" % path)
        return
    text = read(target)
    code_m, name_m = re.search(code_re, text), re.search(name_re, text)
    if not code_m or not name_m:
        fail("fdroid UpdateCheckData regexes do not match %s" % path)
    elif (name_m.group(1), int(code_m.group(1))) != (version_name, version_code):
        fail(
            "fdroid UpdateCheckData reads %s+%s from %s, pubspec says %s+%s"
            % (name_m.group(1), code_m.group(1), path, version_name, version_code)
        )


def png_info(path):
    """(width, height, colour type) of a PNG, or None if it isn't one."""
    with open(path, "rb") as fh:
        head = fh.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    w, h = struct.unpack(">II", head[16:24])
    return w, h, head[25]


def check_images():
    images = os.path.join(LISTINGS, "en-US", "images")
    for name, size in IMAGE_SIZES.items():
        path = os.path.join(images, name)
        if not os.path.isfile(path):
            fail("en-US: missing images/%s" % name)
            continue
        info = png_info(path)
        if info is None or info[:2] != size:
            fail("en-US: images/%s is %s, expected a %dx%d PNG" % (name, info and info[:2], size[0], size[1]))


IOS_ICON = os.path.join(REPO, "app", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")


def check_ios_icon():
    """App Store validation rejects app icons with an alpha channel."""
    if not os.path.isfile(IOS_ICON):
        fail("missing %s (node tools/gen_store_graphics.js)" % os.path.relpath(IOS_ICON, REPO))
        return
    info = png_info(IOS_ICON)
    if info is None or info[:2] != (1024, 1024):
        fail("iOS app icon is %s, expected 1024x1024" % (info and info[:2],))
    elif info[2] != 2:
        fail("iOS app icon has PNG colour type %d; it must be 2 (RGB, no alpha)" % info[2])


def check_listings(version_code):
    if not os.path.isdir(LISTINGS):
        fail("missing fastlane listings directory: %s" % LISTINGS)
        return []

    locales = sorted(
        d for d in os.listdir(LISTINGS) if os.path.isdir(os.path.join(LISTINGS, d))
    )
    if "en-US" not in locales:
        fail("no en-US listing (F-Droid's fallback locale)")

    for loc in locales:
        base = os.path.join(LISTINGS, loc)

        for name, limit in LIMITS.items():
            path = os.path.join(base, name)
            if not os.path.isfile(path):
                fail("%s: missing %s" % (loc, name))
                continue
            text = read(path).strip()
            if not text:
                fail("%s: %s is empty" % (loc, name))
            elif len(text) > limit:
                fail("%s: %s is %d chars, over the %d limit" % (loc, name, len(text), limit))

        if version_code is None:
            continue

        changelog = os.path.join(base, "changelogs", "%d.txt" % version_code)
        if not os.path.isfile(changelog):
            fail(
                "%s: no changelog for versionCode %d (expected changelogs/%d.txt)"
                % (loc, version_code, version_code)
            )
            continue
        text = read(changelog)
        if not text.strip():
            fail("%s: changelogs/%d.txt is empty" % (loc, version_code))
        elif len(text) > CHANGELOG_MAX_CHARS:
            fail(
                "%s: changelogs/%d.txt is %d chars, over F-Droid's %d limit"
                % (loc, version_code, len(text), CHANGELOG_MAX_CHARS)
            )

    return locales


def check_app_locales_have_listings(store_locales):
    """Every language the app ships in needs a store listing, and vice versa.
    Iterating the listing directories alone cannot catch a listing that was
    never created for a newly added app language."""
    app_locales = set()
    for name in os.listdir(ARB_DIR):
        m = re.fullmatch(r"app_([A-Za-z]{2,3})\.arb", name)
        if m:
            app_locales.add(m.group(1).lower())
    if not app_locales:
        fail("no app_<locale>.arb files found in %s" % ARB_DIR)
        return

    # Store dirs are region-qualified (ru-RU, ka-GE) or bare (uk); compare on
    # the language subtag only.
    store_languages = {loc.split("-")[0].lower() for loc in store_locales}
    for lang in sorted(app_locales - store_languages):
        fail("app ships locale '%s' (app_%s.arb) but no fastlane store listing exists for it" % (lang, lang))
    for lang in sorted(store_languages - app_locales):
        fail("fastlane has a store listing for '%s' but the app has no app_%s.arb" % (lang, lang))
    print("app locales: %s" % ", ".join(sorted(app_locales)))


def main():
    version_name, version_code = read_pubspec_version()
    print("pubspec version: %s+%s" % (version_name, version_code))

    check_app_id()
    check_flutter_pin()
    check_fdroid(version_name, version_code)
    locales = check_listings(version_code)
    print("store locales checked: %s" % ", ".join(locales))
    check_images()
    check_ios_icon()
    check_app_locales_have_listings(locales)

    if problems:
        print("\n%d problem(s):" % len(problems), file=sys.stderr)
        for p in problems:
            print("  - %s" % p, file=sys.stderr)
        return 1

    print("\nstore metadata OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
