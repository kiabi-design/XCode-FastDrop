#!/usr/bin/env python3
"""Generates FastDrop.xcodeproj (project.pbxproj + shared scheme) from the files in FastDrop/.

Run from anywhere:  python3 scripts/generate_xcodeproj.py
Every *.swift file under FastDrop/ is added to the target automatically;
*.xcassets folders are added as resources. IDs are deterministic (MD5 of the path).
"""
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "FastDrop"
BUNDLE_ID = "com.fastdrop"
VERSION = "1.4"
BUILD = "1"
DEPLOYMENT_TARGET = "17.0"


def uid(name: str) -> str:
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()


# ---------- old-style plist serializer ----------

_SAFE = re.compile(r"^[A-Za-z0-9_./$]+$")


def q(value) -> str:
    s = str(value)
    if s and _SAFE.match(s):
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def fmt(value, level: int) -> str:
    tab = "\t" * level
    inner = "\t" * (level + 1)
    if isinstance(value, dict):
        if not value:
            return "{\n" + tab + "}"
        lines = ["{"]
        for k, v in value.items():
            lines.append(f"{inner}{q(k)} = {fmt(v, level + 1)};")
        lines.append(tab + "}")
        return "\n".join(lines)
    if isinstance(value, list):
        if not value:
            return "(\n" + tab + ")"
        lines = ["("]
        for v in value:
            lines.append(f"{inner}{fmt(v, level + 1)},")
        lines.append(tab + ")")
        return "\n".join(lines)
    return q(value)


# ---------- collect files ----------

src_root = ROOT / APP
objects = {}          # id -> dict
sources = []          # build file ids (swift + metal)
resources = []        # build file ids
metal_count = [0]     # track .metal files (mutable for closure)


def add(obj_id, obj):
    objects[obj_id] = obj
    return obj_id


def build_group(directory: Path, rel: str) -> str:
    children = []
    entries = sorted(directory.iterdir(), key=lambda p: (not p.is_dir() or p.suffix == ".xcassets", p.name.lower()))
    for entry in entries:
        if entry.name.startswith("."):
            continue
        entry_rel = f"{rel}/{entry.name}"
        if entry.is_dir() and entry.suffix != ".xcassets":
            children.append(build_group(entry, entry_rel))
        elif entry.suffix == ".swift":
            fid = uid("fref:" + entry_rel)
            bid = uid("bfile:" + entry_rel)
            add(fid, {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.swift",
                      "path": entry.name, "sourceTree": "<group>"})
            add(bid, {"isa": "PBXBuildFile", "fileRef": fid})
            sources.append(bid)
            children.append(fid)
        elif entry.suffix == ".metal":
            fid = uid("fref:" + entry_rel)
            bid = uid("bfile:" + entry_rel)
            add(fid, {"isa": "PBXFileReference", "lastKnownFileType": "sourcecode.metal",
                      "path": entry.name, "sourceTree": "<group>"})
            add(bid, {"isa": "PBXBuildFile", "fileRef": fid})
            sources.append(bid)
            metal_count[0] += 1
            children.append(fid)
        elif entry.suffix == ".xcassets":
            fid = uid("fref:" + entry_rel)
            bid = uid("bfile:" + entry_rel)
            add(fid, {"isa": "PBXFileReference", "lastKnownFileType": "folder.assetcatalog",
                      "path": entry.name, "sourceTree": "<group>"})
            add(bid, {"isa": "PBXBuildFile", "fileRef": fid})
            resources.append(bid)
            children.append(fid)
        elif entry.name == "Info.plist":
            fid = uid("fref:" + entry_rel)
            add(fid, {"isa": "PBXFileReference", "lastKnownFileType": "text.plist.xml",
                      "path": entry.name, "sourceTree": "<group>"})
            children.append(fid)
    gid = uid("group:" + rel)
    group = {"isa": "PBXGroup", "children": children, "path": directory.name, "sourceTree": "<group>"}
    return add(gid, group)


app_group = build_group(src_root, APP)

product_ref = add(uid("product"), {"isa": "PBXFileReference", "explicitFileType": "wrapper.application",
                                    "includeInIndex": 0, "path": f"{APP}.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
products_group = add(uid("group:Products"), {"isa": "PBXGroup", "children": [product_ref],
                                              "name": "Products", "sourceTree": "<group>"})
main_group = add(uid("group:Main"), {"isa": "PBXGroup", "children": [app_group, products_group],
                                      "sourceTree": "<group>"})

src_phase = add(uid("phase:sources"), {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647,
                                        "files": sources, "runOnlyForDeploymentPostprocessing": 0})
fw_phase = add(uid("phase:frameworks"), {"isa": "PBXFrameworksBuildPhase", "buildActionMask": 2147483647,
                                          "files": [], "runOnlyForDeploymentPostprocessing": 0})
res_phase = add(uid("phase:resources"), {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647,
                                          "files": resources, "runOnlyForDeploymentPostprocessing": 0})

common = {
    "SDKROOT": "iphoneos",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SUPPORTS_MACCATALYST": "NO",
}
prj_debug = add(uid("cfg:prj:Debug"), {"isa": "XCBuildConfiguration", "name": "Debug", "buildSettings": {
    **common, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_COMPILATION_MODE": "incremental"}})
prj_release = add(uid("cfg:prj:Release"), {"isa": "XCBuildConfiguration", "name": "Release", "buildSettings": {
    **common, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "COPY_PHASE_STRIP": "NO",
    "SWIFT_OPTIMIZATION_LEVEL": "-O", "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}})

target_settings = {
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": BUILD,
    "MARKETING_VERSION": VERSION,
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": f"{APP}/Info.plist",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "TARGETED_DEVICE_FAMILY": "1,2",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "FRAMEWORK_SEARCH_PATHS": ["$(inherited)"],
    "OTHER_LDFLAGS": ["-framework", "Metal", "-framework", "MetalKit"],
}
tgt_debug = add(uid("cfg:tgt:Debug"), {"isa": "XCBuildConfiguration", "name": "Debug", "buildSettings": target_settings})
tgt_release = add(uid("cfg:tgt:Release"), {"isa": "XCBuildConfiguration", "name": "Release", "buildSettings": target_settings})

prj_cfg_list = add(uid("cfglist:prj"), {"isa": "XCConfigurationList", "buildConfigurations": [prj_debug, prj_release],
                                         "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})
tgt_cfg_list = add(uid("cfglist:tgt"), {"isa": "XCConfigurationList", "buildConfigurations": [tgt_debug, tgt_release],
                                         "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})

target_id = add(uid("target"), {
    "isa": "PBXNativeTarget", "buildConfigurationList": tgt_cfg_list,
    "buildPhases": [src_phase, fw_phase, res_phase], "buildRules": [], "dependencies": [],
    "name": APP, "productName": APP, "productReference": product_ref,
    "productType": "com.apple.product-type.application"})

project_id = add(uid("project"), {
    "isa": "PBXProject",
    "attributes": {"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 1500, "LastUpgradeCheck": 1500,
                   "TargetAttributes": {target_id: {"CreatedOnToolsVersion": "15.0"}}},
    "buildConfigurationList": prj_cfg_list, "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en",
    "hasScannedForEncodings": 0, "knownRegions": ["en", "ru", "Base"],
    "mainGroup": main_group, "productRefGroup": products_group, "projectDirPath": "", "projectRoot": "",
    "targets": [target_id]})

# ---------- write pbxproj ----------

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
order = ["PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget",
         "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "XCBuildConfiguration", "XCConfigurationList"]
for isa in order:
    items = sorted((i, o) for i, o in objects.items() if o["isa"] == isa)
    if not items:
        continue
    out.append(f"/* Begin {isa} section */")
    for obj_id, obj in items:
        out.append(f"\t\t{obj_id} = {fmt(obj, 2)};")
    out.append(f"/* End {isa} section */")
    out.append("")
out += ["\t};", f"\trootObject = {project_id};", "}", ""]

proj_dir = ROOT / f"{APP}.xcodeproj"
proj_dir.mkdir(exist_ok=True)
(proj_dir / "project.pbxproj").write_text("\n".join(out), encoding="utf-8", newline="\n")

# ---------- shared scheme ----------

scheme_dir = proj_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" '
       f'BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:{APP}.xcodeproj">'
       f'</BuildableReference>')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
(scheme_dir / f"{APP}.xcscheme").write_text(scheme, encoding="utf-8", newline="\n")

swift_count = len(sources) - metal_count[0]
print(f"Generated {APP}.xcodeproj with {swift_count} Swift files, {metal_count[0]} Metal files, {len(resources)} resources")
