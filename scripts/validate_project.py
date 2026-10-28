#!/usr/bin/env python3
"""Validate Xcode project references/configuration without Xcode or third-party packages."""
import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class OpenStep:
    def __init__(self, text):
        tokens = re.findall(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text, re.S)
        self.tokens = [t for t in tokens if not t.startswith(("//", "/*"))]
        self.index = 0

    def take(self, expected=None):
        token = self.tokens[self.index]
        self.index += 1
        if expected is not None and token != expected:
            raise ValueError(f"Expected {expected}, got {token}")
        return token

    def parse(self):
        token = self.take()
        if token == "{":
            result = {}
            while self.tokens[self.index] != "}":
                key = self.parse()
                self.take("=")
                if key in result:
                    raise ValueError(f"Duplicate key: {key}")
                result[key] = self.parse()
                self.take(";")
            self.take("}")
            return result
        if token == "(":
            result = []
            while self.tokens[self.index] != ")":
                result.append(self.parse())
                if self.tokens[self.index] == ",":
                    self.take(",")
            self.take(")")
            return result
        return json.loads(token) if token.startswith('"') else token


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    parser = OpenStep((ROOT / "ExifBye.xcodeproj/project.pbxproj").read_text())
    document = parser.parse()
    require(parser.index == len(parser.tokens), "Unparsed project content")
    objects = document["objects"]
    project = objects[document["rootObject"]]
    require(project["isa"] == "PBXProject", "Invalid project root")
    require(len(project["targets"]) == 2, "App and test targets required")
    for group in (o for o in objects.values() if o["isa"] == "PBXGroup"):
        for ref in group["children"]:
            require(ref in objects, f"Missing group child: {ref}")
    for target_ref in project["targets"]:
        target = objects[target_ref]
        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        require({objects[c]["name"] for c in configs} == {"Debug", "Release"}, "Missing build configurations")
        compiled = set()
        for phase_ref in target["buildPhases"]:
            phase = objects[phase_ref]
            for build_ref in phase["files"]:
                file_ref = objects[build_ref]["fileRef"]
                require(file_ref in objects, "Dangling build reference")
                if phase["isa"] == "PBXSourcesBuildPhase":
                    require(file_ref not in compiled, "Duplicate compilation unit")
                    compiled.add(file_ref)
        folder = "Sources" if target["name"] == "ExifBye" else "Tests"
        expected = {p.name for p in (ROOT / folder).glob("*.swift")}
        require({objects[r]["path"] for r in compiled} == expected, f"Missing/extra {folder} compilation units")
        require(all((ROOT / folder / objects[r]["path"]).is_file() for r in compiled), "Missing Swift source")
        require(objects[target["productReference"]]["path"].endswith((".app", ".xctest")), "Invalid product")
        for dependency in target["dependencies"]:
            require(objects[dependency]["target"] in project["targets"], "Invalid target dependency")
    for ref in objects[project["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[ref]["buildSettings"]
        require(settings["IPHONEOS_DEPLOYMENT_TARGET"] == "16.0", "iOS 16 minimum required")
        require(settings["SWIFT_VERSION"] == "5.0", "Swift 5 language mode required")
    with (ROOT / "Support/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    require(bool(info["NSPhotoLibraryAddUsageDescription"]), "Missing add-only Photos permission text")
    require("NSPhotoLibraryUsageDescription" not in info, "Unexpected full-library permission")
    require(info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)", "Hardcoded bundle ID")
    scheme = ET.parse(ROOT / "ExifBye.xcodeproj/xcshareddata/xcschemes/ExifBye.xcscheme")
    for reference in scheme.findall(".//BuildableReference"):
        require(reference.attrib["BlueprintIdentifier"] in project["targets"], "Invalid scheme target")
    testables = scheme.findall(".//TestableReference")
    require(len(testables) == 1 and testables[0].attrib["skipped"] == "NO", "Tests missing/disabled")
    tests = sum(len(re.findall(r"func test\w+\(", p.read_text())) for p in (ROOT / "Tests").glob("*.swift"))
    require(tests == 7, f"Expected 7 XCTest methods, found {tests}")
    print(f"PASS: {len(objects)} project objects; app/test sources; plist; shared scheme; iOS 16/Swift 5 settings")
    print("NOT RUN: Apple SDK compilation, 7 XCTest methods, device installation and Photos permissions")


if __name__ == "__main__":
    main()
