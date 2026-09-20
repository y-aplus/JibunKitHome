#!/usr/bin/env python3
"""Verify and ad-hoc sign the actual embedded Share product before its host."""
import argparse
import pathlib
import plistlib
import subprocess


def validate_metadata(host, share, entitlements, kind="Share"):
    assert kind in {"Share", "Action"}, "Unknown incoming extension kind"
    assert share["CFBundleIdentifier"] == host["CFBundleIdentifier"] + "." + kind
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "JibunKitAppGroup"):
        assert share[key] == host[key], f"Share/host {key} mismatch"
    assert share["JibunKitAppGroup"] in entitlements["com.apple.security.application-groups"]
    extension = share["NSExtension"]
    assert extension["NSExtensionPointIdentifier"] == {"Share": "com.apple.share-services", "Action": "com.apple.ui-services"}[kind]
    assert extension["NSExtensionPrincipalClass"].endswith(f".{kind}ViewController")
    assert "$" not in extension["NSExtensionPrincipalClass"], "Unexpanded principal class"
    rule = extension["NSExtensionAttributes"]["NSExtensionActivationRule"]
    assert isinstance(rule, str) and "UTI-CONFORMS-TO 'public.data'" in rule
    assert "TRUEPREDICATE" not in rule.upper(), "Development-only activation rule"
    assert host["LSSupportsOpeningDocumentsInPlace"] is True
    assert any("public.data" in item.get("LSItemContentTypes", []) for item in host["CFBundleDocumentTypes"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=pathlib.Path)
    parser.add_argument("--entitlements-root", required=True, type=pathlib.Path)
    parser.add_argument("--kind", choices=["Share", "Action"], default="Share")
    args = parser.parse_args()
    share = args.app / f"PlugIns/JibunKit{args.kind}_Extension.appex"
    host_info = plistlib.loads((args.app / "Info.plist").read_bytes())
    share_info = plistlib.loads((share / "Info.plist").read_bytes())
    paths = list(args.entitlements_root.rglob(f"JibunKit{args.kind}-Extension.entitlements"))
    assert len(paths) == 1, f"Expected one Share entitlement file: {paths}"
    entitlements = plistlib.loads(paths[0].read_bytes())
    validate_metadata(host_info, share_info, entitlements, args.kind)
    executable = share / share_info["CFBundleExecutable"]
    assert executable.is_file() and executable.stat().st_size > 0
    architecture = subprocess.check_output(["file", str(executable)], text=True)
    assert "arm64" in architecture, architecture
    subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                    "--generate-entitlement-der", "--entitlements", str(paths[0]), str(share)], check=True)
    subprocess.run(["codesign", "--verify", "--strict", str(share)], check=True)
    signed = subprocess.check_output(["codesign", "--display", "--entitlements", ":-", str(share)])
    actual = plistlib.loads(signed)
    assert actual["com.apple.security.application-groups"] == entitlements["com.apple.security.application-groups"]
    print(f"passed: embedded {args.kind} executable/arm64/metadata/version/App Group/signature: {share}")


if __name__ == "__main__":
    main()
