#!/usr/bin/env bash
set -euo pipefail

apk_dir=${1:?usage: verify-apk.sh APK_DIR EXPECTED_HARMONY_VERSION}
expected_version=${2:?usage: verify-apk.sh APK_DIR EXPECTED_HARMONY_VERSION}
[[ $expected_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-harmony\.[0-9]+$ ]] || { echo "invalid expected Harmony version" >&2; exit 2; }

sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
[[ -n $sdk && -d $sdk/build-tools ]] || { echo "ANDROID_HOME/ANDROID_SDK_ROOT with build-tools is required" >&2; exit 2; }
tools=$(printf '%s\n' "$sdk"/build-tools/* | sort -V | tail -n1)
for tool in aapt2 apksigner; do [[ -x $tools/$tool ]] || { echo "missing $tool in $tools" >&2; exit 2; }; done
analyzer=$sdk/cmdline-tools/latest/bin/apkanalyzer
[[ -x $analyzer ]] || { echo "missing apkanalyzer at $analyzer" >&2; exit 2; }
command -v unzip >/dev/null || { echo "unzip is required" >&2; exit 2; }

shopt -s nullglob
apks=("$apk_dir"/*.apk)
[[ ${#apks[@]} -eq 1 ]] || { echo "expected exactly one APK, found ${#apks[@]}" >&2; exit 1; }
apk=${apks[0]}
sha1_file="$apk.sha1"
[[ -f $sha1_file ]] || { echo "missing SHA-1 sidecar: $(basename "$sha1_file")" >&2; exit 1; }
actual_sha1=$(sha1sum "$apk" | awk '{print $1}')
sidecar_sha1=$(awk 'NR==1 {print $1}' "$sha1_file" | tr '[:upper:]' '[:lower:]')
[[ $sidecar_sha1 =~ ^[0-9a-f]{40}$ && $sidecar_sha1 == "$actual_sha1" ]] || { echo "SHA-1 sidecar mismatch" >&2; exit 1; }

badging=$("$tools/aapt2" dump badging "$apk")
package_meta=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)' versionCode='\([^']*\)' versionName='\([^']*\)'.*/\1 \2 \3/p" | head -n1)
read -r package version_code version_name <<<"$package_meta"
[[ $package == me.him188.ani.harmony ]] || { echo "unexpected package name: $package" >&2; exit 1; }
[[ $version_name == "$expected_version" ]] || { echo "unexpected versionName: $version_name" >&2; exit 1; }

abis=$(unzip -Z1 "$apk" | awk -F/ '$1=="lib" && NF>=3 {print $2}' | sort -u | paste -sd, -)
[[ $abis == arm64-v8a ]] || { echo "unexpected native ABI set: ${abis:-none}" >&2; exit 1; }

cert_output=$("$tools/apksigner" verify --print-certs "$apk")
[[ $(printf '%s\n' "$cert_output" | grep -Ec '^Signer #[0-9]+ certificate SHA-256 digest:') == 1 ]] || { echo "expected exactly one APK signer" >&2; exit 1; }
printf '%s\n' "$cert_output" | grep -qi '^Signer #1 certificate SHA-256 digest: 50907c1de76a92991797ed8c5c1feb5df56e180634738b538bddc81735dda10b$' || {
    echo "APK signer certificate SHA-256 does not match expected certificate" >&2; exit 1;
}

manifest=$("$analyzer" manifest print "$apk")
printf '%s\n' "$manifest" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
ns = "{http://schemas.android.com/apk/res/android}"
services = {s.get(ns+"name", ""): s for s in root.findall(".//service")}
required = {
  "me.him188.ani.app.domain.torrent.service.HttpCacheService": ("mediaPlayback", None),
  "me.him188.ani.app.domain.torrent.service.PikPakCacheService": ("mediaPlayback", None),
  "me.him188.ani.app.domain.torrent.service.AniTorrentServiceApi34": (None, ":torrent_service"),
  "me.him188.ani.app.domain.torrent.service.AniTorrentServiceApiDefault": (None, ":torrent_service"),
}
for name, (fgs, process) in required.items():
    service = services.get(name)
    if service is None:
        raise SystemExit(f"missing service in APK manifest: {name}")
    actual_type = service.get(ns+"foregroundServiceType", "")
    if fgs and actual_type != fgs:
        try:
            matches = int(actual_type, 0) == 2
        except ValueError:
            matches = False
        if not matches:
            raise SystemExit(f"unexpected foregroundServiceType for {name}: {actual_type}")
    if process is None and service.get(ns+"process") not in (None, "me.him188.ani.harmony"):
        raise SystemExit(f"expected main process for {name}")
    if process and service.get(ns+"process") != process:
        raise SystemExit(f"unexpected process for {name}")
'

apk_sha256=$(sha256sum "$apk" | awk '{print $1}')
apk_size=$(stat -c '%s' "$apk")
printf 'APK: %s\nSize: %s bytes\nSHA-256: %s\nPackage: %s\nVersion: %s (versionCode %s)\nABIs: %s\nSignature: verified; expected certificate matched\nManifest: service process/type checks passed\nSHA-1 sidecar: matched\n' \
  "$(basename "$apk")" "$apk_size" "$apk_sha256" "$package" "$version_name" "$version_code" "$abis"
