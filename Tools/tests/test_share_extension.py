import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("share_extension", Path(__file__).parents[1] / "verify-share-extension.py")
share_extension = importlib.util.module_from_spec(spec)
spec.loader.exec_module(share_extension)


class ShareExtensionMetadataTests(unittest.TestCase):
    def setUp(self):
        self.host = {
            "CFBundleIdentifier": "com.jibunkit.app", "CFBundleShortVersionString": "0.8.0",
            "CFBundleVersion": "9", "JibunKitAppGroup": "group.example",
            "LSSupportsOpeningDocumentsInPlace": True,
            "CFBundleDocumentTypes": [{"LSItemContentTypes": ["public.data"]}],
        }
        self.share = copy.deepcopy(self.host)
        self.share["CFBundleIdentifier"] += ".Share"
        self.share["NSExtension"] = {
            "NSExtensionPointIdentifier": "com.apple.share-services",
            "NSExtensionPrincipalClass": "JibunKitShare_Extension.ShareViewController",
            "NSExtensionAttributes": {"NSExtensionActivationRule": "ANY types UTI-CONFORMS-TO 'public.data'"},
        }
        self.entitlements = {"com.apple.security.application-groups": ["group.example"]}

    def test_matching_embedded_product(self):
        share_extension.validate_metadata(self.host, self.share, self.entitlements)

    def test_action_requires_its_own_identity_point_and_principal(self):
        action = copy.deepcopy(self.share)
        action["CFBundleIdentifier"] = self.host["CFBundleIdentifier"] + ".Action"
        extension = action["NSExtension"]
        extension["NSExtensionPointIdentifier"] = "com.apple.ui-services"
        extension["NSExtensionPrincipalClass"] = "JibunKitAction_Extension.ActionViewController"
        share_extension.validate_metadata(self.host, action, self.entitlements, "Action")
        for key, wrong in [("NSExtensionPointIdentifier", "com.apple.share-services"),
                           ("NSExtensionPrincipalClass", "Module.ShareViewController")]:
            broken = copy.deepcopy(action)
            broken["NSExtension"][key] = wrong
            with self.assertRaises(AssertionError):
                share_extension.validate_metadata(self.host, broken, self.entitlements, "Action")
        with self.assertRaises(AssertionError):
            share_extension.validate_metadata(self.host, self.share, self.entitlements, "Action")
        with self.assertRaises(AssertionError):
            share_extension.validate_metadata(self.host, action, self.entitlements)

    def test_wrong_product_version_identity_and_group_fail(self):
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "JibunKitAppGroup"):
            with self.subTest(key=key):
                damaged = copy.deepcopy(self.share)
                damaged[key] = "incorrect"
                with self.assertRaises(AssertionError):
                    share_extension.validate_metadata(self.host, damaged, self.entitlements)
        with self.assertRaises(AssertionError):
            share_extension.validate_metadata(self.host, self.share, {"com.apple.security.application-groups": ["group.other"]})

    def test_unexpanded_entry_or_development_activation_fails(self):
        for principal, rule in (("$(PRODUCT_MODULE_NAME).ShareViewController", "UTI-CONFORMS-TO 'public.data'"),
                                ("Module.ShareViewController", "TRUEPREDICATE")):
            with self.subTest(principal=principal, rule=rule):
                damaged = copy.deepcopy(self.share)
                damaged["NSExtension"]["NSExtensionPrincipalClass"] = principal
                damaged["NSExtension"]["NSExtensionAttributes"]["NSExtensionActivationRule"] = rule
                with self.assertRaises(AssertionError):
                    share_extension.validate_metadata(self.host, damaged, self.entitlements)


if __name__ == "__main__":
    unittest.main()
