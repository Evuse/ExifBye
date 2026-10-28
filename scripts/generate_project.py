#!/usr/bin/env python3
"""Generate the checked-in Xcode 16.2 project with Python only; no XcodeGen required."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def obj(object_key, isa, **fields):
    key = ident(object_key)
    objects[key] = {"isa": isa, **fields}
    return key


def serialize(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, dict):
        lines = ["{"]
        lines.extend(f"{indent}\t{json.dumps(k)} = {serialize(v, depth + 1)};" for k, v in value.items())
        lines.append(indent + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        return "(\n" + "".join(f"{indent}\t{serialize(v, depth + 1)},\n" for v in value) + indent + ")"
    return json.dumps(str(value))


def files(folder):
    references = []
    builds = []
    for path in sorted((ROOT / folder).glob("*.swift")):
        ref = obj(str(path.relative_to(ROOT)), "PBXFileReference",
                  lastKnownFileType="sourcecode.swift", path=path.name, sourceTree="<group>")
        references.append(ref)
        builds.append(obj(f"build-{folder}-{path.name}", "PBXBuildFile", fileRef=ref))
    group = obj(f"group-{folder}", "PBXGroup", children=references, path=folder, sourceTree="<group>")
    return group, builds


sources_group, app_builds = files("Sources")
tests_group, test_builds = files("Tests")
info = obj("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Info.plist", sourceTree="<group>")
assets = obj("assets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Assets.xcassets", sourceTree="<group>")
assets_build = obj("assets-build", "PBXBuildFile", fileRef=assets)
support_group = obj("support", "PBXGroup", children=[info, assets], path="Support", sourceTree="<group>")
app_product = obj("product-app", "PBXFileReference", explicitFileType="wrapper.application",
                  includeInIndex=0, path="ExifBye.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = obj("product-tests", "PBXFileReference", explicitFileType="wrapper.cfbundle",
                   includeInIndex=0, path="ExifByeTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products_group = obj("products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main_group = obj("main-group", "PBXGroup", children=[sources_group, support_group, tests_group, products_group], sourceTree="<group>")


def configurations(name, common):
    refs = []
    for mode in ("Debug", "Release"):
        settings = dict(common)
        settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O"})
        if mode == "Debug":
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                             "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG", "ONLY_ACTIVE_ARCH": "YES"})
        else:
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule"})
        refs.append(obj(f"config-{name}-{mode}", "XCBuildConfiguration", buildSettings=settings, name=mode))
    return obj(f"config-list-{name}", "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


project_config = configurations("project", {
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos",
    "IPHONEOS_DEPLOYMENT_TARGET": "16.0", "SWIFT_VERSION": "5.0", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "CLANG_WARN_UNREACHABLE_CODE": "YES",
})
app_config = configurations("app", {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.exifbye.personal",
    "INFOPLIST_FILE": "Support/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "", "TARGETED_DEVICE_FAMILY": "1,2",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
})
test_config = configurations("tests", {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "app.exifbye.personal.tests",
    "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
    "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ExifBye.app/ExifBye", "BUNDLE_LOADER": "$(TEST_HOST)",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
})


def phases(name, builds):
    source = obj(f"sources-{name}", "PBXSourcesBuildPhase", buildActionMask=2147483647,
                 files=builds, runOnlyForDeploymentPostprocessing=0)
    frameworks = obj(f"frameworks-{name}", "PBXFrameworksBuildPhase", buildActionMask=2147483647,
                     files=[], runOnlyForDeploymentPostprocessing=0)
    resources = obj(f"resources-{name}", "PBXResourcesBuildPhase", buildActionMask=2147483647,
                    files=[assets_build] if name == "app" else [], runOnlyForDeploymentPostprocessing=0)
    return [source, frameworks, resources]


app = obj("target-app", "PBXNativeTarget", buildConfigurationList=app_config,
          buildPhases=phases("app", app_builds), buildRules=[], dependencies=[], name="ExifBye",
          productName="ExifBye", productReference=app_product, productType="com.apple.product-type.application")
proxy = obj("test-proxy", "PBXContainerItemProxy", containerPortal=ident("project"), proxyType=1,
            remoteGlobalIDString=app, remoteInfo="ExifBye")
dependency = obj("test-dependency", "PBXTargetDependency", target=app, targetProxy=proxy)
tests = obj("target-tests", "PBXNativeTarget", buildConfigurationList=test_config,
            buildPhases=phases("tests", test_builds), buildRules=[], dependencies=[dependency], name="ExifByeTests",
            productName="ExifByeTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
project = obj("project", "PBXProject", attributes={
    "BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1620", "LastSwiftUpdateCheck": "1620",
    "TargetAttributes": {app: {"CreatedOnToolsVersion": "16.2"}, tests: {"CreatedOnToolsVersion": "16.2", "TestTargetID": app}}
}, buildConfigurationList=project_config, compatibilityVersion="Xcode 14.0", developmentRegion="it",
    hasScannedForEncodings=0, knownRegions=["it", "en", "Base"], mainGroup=main_group,
    productRefGroup=products_group, projectDirPath="", projectRoot="", targets=[app, tests])

document = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
project_dir = ROOT / "ExifBye.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(document) + "\n")
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1620" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
  <BuildActionEntries>
   <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
    <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ExifBye.app" BlueprintName="ExifBye" ReferencedContainer="container:ExifBye.xcodeproj"/>
   </BuildActionEntry>
  </BuildActionEntries>
 </BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{tests}" BuildableName="ExifByeTests.xctest" BlueprintName="ExifByeTests" ReferencedContainer="container:ExifBye.xcodeproj"/></TestableReference></Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ExifBye.app" BlueprintName="ExifBye" ReferencedContainer="container:ExifBye.xcodeproj"/></BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="ExifBye.app" BlueprintName="ExifBye" ReferencedContainer="container:ExifBye.xcodeproj"/></BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "ExifBye.xcscheme").write_text(scheme)
print(f"Generated project: {len(app_builds)} app files, {len(test_builds)} test files")
