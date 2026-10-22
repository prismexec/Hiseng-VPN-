#!/usr/bin/env python3
"""Writes altstore.json: an install source (AltStore format, also read by
ESign, Feather and SideStore) pointing at the latest iOS release.

usage: altstore.py BUILD VERSION IPA_PATH > altstore.json
"""
import datetime
import json
import os
import sys

REPO = os.environ.get("SOURCE_REPO", "prismexec/Hiseng-VPN-")
build, version, ipa = sys.argv[1], sys.argv[2], sys.argv[3]
name = os.path.basename(ipa)
size = os.path.getsize(ipa)
url = f"https://github.com/{REPO}/releases/download/ios-{build}/{name}"
icon = f"https://raw.githubusercontent.com/{REPO}/main/ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
about = "VPN-клиент OpenFlux: вставьте ключ openflux:// и нажмите кнопку."
notes = f"Сборка {build}"

app = {
    "name": "Hiseng VPN",
    "bundleIdentifier": "com.hiseng.vpn",
    "developerName": "Hiseng",
    "subtitle": "VPN на OpenFlux",
    "localizedDescription": about,
    "iconURL": icon,
    "tintColor": "6750A4",
    "category": "utilities",
    "versions": [{
        "version": version,
        "buildVersion": build,
        "date": date,
        "localizedDescription": notes,
        "downloadURL": url,
        "size": size,
        "minOSVersion": "15.0",
    }],
    # Fields older readers (ESign, Feather) use.
    "version": version,
    "versionDate": date,
    "versionDescription": notes,
    "downloadURL": url,
    "size": size,
    "appPermissions": {"entitlements": [], "privacy": {}},
}

json.dump({
    "name": "Hiseng VPN",
    "identifier": "com.hiseng.vpn.source",
    "subtitle": "Обновления Hiseng VPN",
    "iconURL": icon,
    "tintColor": "6750A4",
    "apps": [app],
    "news": [],
}, sys.stdout, ensure_ascii=False, indent=2)
print()
