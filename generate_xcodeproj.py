#!/usr/bin/env python3
"""
Generates BarsysAppSwiftUI.xcodeproj from the Swift sources in BarsysAppSwiftUI/.

Run this once to produce an openable Xcode project. Re-run if you add new files.

No external dependencies. Produces a project with:
- iOS 16.0 deployment target
- SwiftUI life cycle
- All .swift files under BarsysAppSwiftUI/ compiled
- Assets.xcassets as a resource
- Camera usage description (for the QR scanner)
"""

import os
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT_NAME = "BarsysAppSwiftUI"
SRC_ROOT = ROOT / PROJECT_NAME
XCODEPROJ = ROOT / f"{PROJECT_NAME}.xcodeproj"

def uid(*parts: str) -> str:
    """Deterministic 24-char uppercase hex ID derived from inputs."""
    h = hashlib.md5("::".join(parts).encode()).hexdigest().upper()
    return h[:24]

# Collect all swift files (relative paths inside project)
swift_files = sorted(
    p.relative_to(SRC_ROOT).as_posix()
    for p in SRC_ROOT.rglob("*.swift")
)

# Collect asset catalogs
asset_catalogs = sorted(
    p.relative_to(SRC_ROOT).as_posix()
    for p in SRC_ROOT.rglob("Assets.xcassets")
    if p.is_dir()
)

# Collect font files
font_files = sorted(
    p.relative_to(SRC_ROOT).as_posix()
    for p in (SRC_ROOT / "Fonts").glob("*")
    if p.is_file() and p.suffix.lower() in {".otf", ".ttf"}
) if (SRC_ROOT / "Fonts").exists() else []

# Collect bundled JSON resources (e.g. Countries.json)
json_files = sorted(
    p.relative_to(SRC_ROOT).as_posix()
    for p in SRC_ROOT.glob("*.json")
    if p.is_file()
)

# Build group tree from file paths
class Node:
    def __init__(self, name, path=""):
        self.name = name
        self.path = path  # source-tree relative path segment
        self.children = {}       # name -> Node
        self.files = []          # list of (name, kind) where kind = "swift"|"asset"
        self.uid = uid("group", path or name)

root_group = Node(PROJECT_NAME, "")

def insert(path: str, kind: str):
    parts = path.split("/")
    node = root_group
    for segment in parts[:-1]:
        child = node.children.get(segment)
        if child is None:
            child_path = (node.path + "/" + segment) if node.path else segment
            child = Node(segment, child_path)
            node.children[segment] = child
        node = child
    node.files.append((parts[-1], kind, path))

for f in swift_files:
    insert(f, "swift")
for a in asset_catalogs:
    insert(a, "asset")
for ff in font_files:
    insert(ff, "font")
for j in json_files:
    insert(j, "json")

# Unique IDs per file
file_ref_ids = {}          # path -> id
build_file_ids = {}        # path -> id
for f in swift_files + asset_catalogs + font_files + json_files:
    file_ref_ids[f] = uid("fileref", f)
    build_file_ids[f] = uid("buildfile", f)

# Product / target / phases / config IDs
PROJECT_ID         = uid("project")
MAIN_GROUP_ID      = uid("mainGroup")
PRODUCTS_GROUP_ID  = uid("productsGroup")
PROJECT_GROUP_ID   = root_group.uid
TARGET_ID          = uid("target")
PRODUCT_REF_ID     = uid("productRef")
SOURCES_PHASE_ID   = uid("sources")
RESOURCES_PHASE_ID = uid("resources")
FRAMEWORKS_PHASE_ID= uid("frameworks")
PROJ_CFG_LIST_ID   = uid("projCfgList")
TGT_CFG_LIST_ID    = uid("tgtCfgList")
PROJ_DEBUG_ID      = uid("projDebug")
PROJ_RELEASE_ID    = uid("projRelease")
TGT_DEBUG_ID       = uid("tgtDebug")
TGT_RELEASE_ID     = uid("tgtRelease")

# --- Build the pbxproj string ---

def section_header(name):
    return f"\n/* Begin {name} section */\n"

def section_footer(name):
    return f"/* End {name} section */\n"

out = []
out.append("// !$*UTF8*$!\n{\n")
out.append("\tarchiveVersion = 1;\n")
out.append("\tclasses = {\n\t};\n")
out.append("\tobjectVersion = 56;\n")
out.append("\tobjects = {\n")

# PBXBuildFile
out.append(section_header("PBXBuildFile"))
for f in swift_files:
    name = os.path.basename(f)
    out.append(f"\t\t{build_file_ids[f]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[f]} /* {name} */; }};\n")
for a in asset_catalogs:
    name = os.path.basename(a)
    out.append(f"\t\t{build_file_ids[a]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[a]} /* {name} */; }};\n")
for ff in font_files:
    name = os.path.basename(ff)
    out.append(f'\t\t{build_file_ids[ff]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[ff]} /* {name} */; }};\n')
for j in json_files:
    name = os.path.basename(j)
    out.append(f'\t\t{build_file_ids[j]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[j]} /* {name} */; }};\n')
out.append(section_footer("PBXBuildFile"))

# PBXFileReference
out.append(section_header("PBXFileReference"))
for f in swift_files:
    name = os.path.basename(f)
    out.append(f'\t\t{file_ref_ids[f]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};\n')
for a in asset_catalogs:
    name = os.path.basename(a)
    out.append(f'\t\t{file_ref_ids[a]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "{name}"; sourceTree = "<group>"; }};\n')
for ff in font_files:
    name = os.path.basename(ff)
    out.append(f'\t\t{file_ref_ids[ff]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = file; path = "{name}"; sourceTree = "<group>"; }};\n')
for j in json_files:
    name = os.path.basename(j)
    out.append(f'\t\t{file_ref_ids[j]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.json; path = "{name}"; sourceTree = "<group>"; }};\n')
# Product reference
out.append(f'\t\t{PRODUCT_REF_ID} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{PROJECT_NAME}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};\n')
out.append(section_footer("PBXFileReference"))

# PBXFrameworksBuildPhase
out.append(section_header("PBXFrameworksBuildPhase"))
out.append(f"\t\t{FRAMEWORKS_PHASE_ID} /* Frameworks */ = {{\n")
out.append("\t\t\tisa = PBXFrameworksBuildPhase;\n")
out.append("\t\t\tbuildActionMask = 2147483647;\n")
out.append("\t\t\tfiles = (\n\t\t\t);\n")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;\n")
out.append("\t\t};\n")
out.append(section_footer("PBXFrameworksBuildPhase"))

# PBXGroup
out.append(section_header("PBXGroup"))

def emit_group(node: Node, is_root=False):
    out.append(f"\t\t{node.uid} /* {node.name} */ = {{\n")
    out.append("\t\t\tisa = PBXGroup;\n")
    out.append("\t\t\tchildren = (\n")
    # Children groups (sorted)
    for child_name in sorted(node.children.keys()):
        child = node.children[child_name]
        out.append(f"\t\t\t\t{child.uid} /* {child.name} */,\n")
    # Files
    for fname, kind, path in sorted(node.files):
        fid = file_ref_ids[path]
        out.append(f"\t\t\t\t{fid} /* {fname} */,\n")
    out.append("\t\t\t);\n")
    if is_root:
        out.append(f'\t\t\tpath = "{PROJECT_NAME}";\n')
    else:
        out.append(f'\t\t\tpath = "{node.name}";\n')
    out.append("\t\t\tsourceTree = \"<group>\";\n")
    out.append("\t\t};\n")
    for child in node.children.values():
        emit_group(child)

# Main group
out.append(f"\t\t{MAIN_GROUP_ID} = {{\n")
out.append("\t\t\tisa = PBXGroup;\n")
out.append("\t\t\tchildren = (\n")
out.append(f"\t\t\t\t{PROJECT_GROUP_ID} /* {PROJECT_NAME} */,\n")
out.append(f"\t\t\t\t{PRODUCTS_GROUP_ID} /* Products */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\tsourceTree = \"<group>\";\n")
out.append("\t\t};\n")
# Products group
out.append(f"\t\t{PRODUCTS_GROUP_ID} /* Products */ = {{\n")
out.append("\t\t\tisa = PBXGroup;\n")
out.append("\t\t\tchildren = (\n")
out.append(f"\t\t\t\t{PRODUCT_REF_ID} /* {PROJECT_NAME}.app */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\tname = Products;\n")
out.append("\t\t\tsourceTree = \"<group>\";\n")
out.append("\t\t};\n")
# Project group + descendants
emit_group(root_group, is_root=True)
out.append(section_footer("PBXGroup"))

# PBXNativeTarget
out.append(section_header("PBXNativeTarget"))
out.append(f"\t\t{TARGET_ID} /* {PROJECT_NAME} */ = {{\n")
out.append("\t\t\tisa = PBXNativeTarget;\n")
out.append(f"\t\t\tbuildConfigurationList = {TGT_CFG_LIST_ID} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;\n")
out.append("\t\t\tbuildPhases = (\n")
out.append(f"\t\t\t\t{SOURCES_PHASE_ID} /* Sources */,\n")
out.append(f"\t\t\t\t{FRAMEWORKS_PHASE_ID} /* Frameworks */,\n")
out.append(f"\t\t\t\t{RESOURCES_PHASE_ID} /* Resources */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\tbuildRules = (\n\t\t\t);\n")
out.append("\t\t\tdependencies = (\n\t\t\t);\n")
out.append(f'\t\t\tname = "{PROJECT_NAME}";\n')
out.append(f'\t\t\tproductName = "{PROJECT_NAME}";\n')
out.append(f"\t\t\tproductReference = {PRODUCT_REF_ID} /* {PROJECT_NAME}.app */;\n")
out.append("\t\t\tproductType = \"com.apple.product-type.application\";\n")
out.append("\t\t};\n")
out.append(section_footer("PBXNativeTarget"))

# PBXProject
out.append(section_header("PBXProject"))
out.append(f"\t\t{PROJECT_ID} /* Project object */ = {{\n")
out.append("\t\t\tisa = PBXProject;\n")
out.append("\t\t\tattributes = {\n")
out.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;\n")
out.append("\t\t\t\tLastSwiftUpdateCheck = 1500;\n")
out.append("\t\t\t\tLastUpgradeCheck = 1500;\n")
out.append("\t\t\t\tTargetAttributes = {\n")
out.append(f"\t\t\t\t\t{TARGET_ID} = {{\n")
out.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n")
out.append("\t\t\t\t\t};\n")
out.append("\t\t\t\t};\n")
out.append("\t\t\t};\n")
out.append(f"\t\t\tbuildConfigurationList = {PROJ_CFG_LIST_ID} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;\n")
out.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n")
out.append("\t\t\tdevelopmentRegion = en;\n")
out.append("\t\t\thasScannedForEncodings = 0;\n")
out.append("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n")
out.append(f"\t\t\tmainGroup = {MAIN_GROUP_ID};\n")
out.append(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP_ID} /* Products */;\n")
out.append("\t\t\tprojectDirPath = \"\";\n")
out.append("\t\t\tprojectRoot = \"\";\n")
out.append("\t\t\ttargets = (\n")
out.append(f"\t\t\t\t{TARGET_ID} /* {PROJECT_NAME} */,\n")
out.append("\t\t\t);\n")
out.append("\t\t};\n")
out.append(section_footer("PBXProject"))

# PBXResourcesBuildPhase
out.append(section_header("PBXResourcesBuildPhase"))
out.append(f"\t\t{RESOURCES_PHASE_ID} /* Resources */ = {{\n")
out.append("\t\t\tisa = PBXResourcesBuildPhase;\n")
out.append("\t\t\tbuildActionMask = 2147483647;\n")
out.append("\t\t\tfiles = (\n")
for a in asset_catalogs:
    out.append(f"\t\t\t\t{build_file_ids[a]} /* {os.path.basename(a)} in Resources */,\n")
for ff in font_files:
    out.append(f"\t\t\t\t{build_file_ids[ff]} /* {os.path.basename(ff)} in Resources */,\n")
for j in json_files:
    out.append(f"\t\t\t\t{build_file_ids[j]} /* {os.path.basename(j)} in Resources */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;\n")
out.append("\t\t};\n")
out.append(section_footer("PBXResourcesBuildPhase"))

# PBXSourcesBuildPhase
out.append(section_header("PBXSourcesBuildPhase"))
out.append(f"\t\t{SOURCES_PHASE_ID} /* Sources */ = {{\n")
out.append("\t\t\tisa = PBXSourcesBuildPhase;\n")
out.append("\t\t\tbuildActionMask = 2147483647;\n")
out.append("\t\t\tfiles = (\n")
for f in swift_files:
    out.append(f"\t\t\t\t{build_file_ids[f]} /* {os.path.basename(f)} in Sources */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;\n")
out.append("\t\t};\n")
out.append(section_footer("PBXSourcesBuildPhase"))

# XCBuildConfiguration
def proj_common_settings():
    return """\
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_VERSION = 5.0;
"""

def target_common_settings():
    fonts_lines = ""
    if font_files:
        fonts_lines = "\t\t\t\tINFOPLIST_KEY_UIAppFonts = (\n"
        for ff in font_files:
            fonts_lines += f'\t\t\t\t\t"{os.path.basename(ff)}",\n'
        fonts_lines += "\t\t\t\t);\n"
    return fonts_lines + """\
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "Barsys uses Bluetooth to discover and connect to your Barsys device.";
\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "Barsys needs camera access to scan QR codes and ingredient barcodes.";
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_BackgroundColor = primaryBackgroundColor;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_ImageName = splashAppIcon;
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.barsys.BarsysAppSwiftUI;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

out.append(section_header("XCBuildConfiguration"))
# Project Debug
out.append(f"\t\t{PROJ_DEBUG_ID} /* Debug */ = {{\n")
out.append("\t\t\tisa = XCBuildConfiguration;\n")
out.append("\t\t\tbuildSettings = {\n")
out.append(proj_common_settings())
out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n")
out.append("\t\t\t\tENABLE_TESTABILITY = YES;\n")
out.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;\n")
out.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n")
out.append("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\n\t\t\t\t\t\"DEBUG=1\",\n\t\t\t\t\t\"$(inherited)\",\n\t\t\t\t);\n")
out.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;\n")
out.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n")
out.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n")
out.append("\t\t\t};\n")
out.append("\t\t\tname = Debug;\n")
out.append("\t\t};\n")
# Project Release
out.append(f"\t\t{PROJ_RELEASE_ID} /* Release */ = {{\n")
out.append("\t\t\tisa = XCBuildConfiguration;\n")
out.append("\t\t\tbuildSettings = {\n")
out.append(proj_common_settings())
out.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n")
out.append("\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n")
out.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n")
out.append("\t\t\t};\n")
out.append("\t\t\tname = Release;\n")
out.append("\t\t};\n")
# Target Debug
out.append(f"\t\t{TGT_DEBUG_ID} /* Debug */ = {{\n")
out.append("\t\t\tisa = XCBuildConfiguration;\n")
out.append("\t\t\tbuildSettings = {\n")
out.append(target_common_settings())
out.append("\t\t\t};\n")
out.append("\t\t\tname = Debug;\n")
out.append("\t\t};\n")
# Target Release
out.append(f"\t\t{TGT_RELEASE_ID} /* Release */ = {{\n")
out.append("\t\t\tisa = XCBuildConfiguration;\n")
out.append("\t\t\tbuildSettings = {\n")
out.append(target_common_settings())
out.append("\t\t\t};\n")
out.append("\t\t\tname = Release;\n")
out.append("\t\t};\n")
out.append(section_footer("XCBuildConfiguration"))

# XCConfigurationList
out.append(section_header("XCConfigurationList"))
out.append(f"\t\t{PROJ_CFG_LIST_ID} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{\n")
out.append("\t\t\tisa = XCConfigurationList;\n")
out.append("\t\t\tbuildConfigurations = (\n")
out.append(f"\t\t\t\t{PROJ_DEBUG_ID} /* Debug */,\n")
out.append(f"\t\t\t\t{PROJ_RELEASE_ID} /* Release */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\tdefaultConfigurationIsVisible = 0;\n")
out.append("\t\t\tdefaultConfigurationName = Release;\n")
out.append("\t\t};\n")
out.append(f"\t\t{TGT_CFG_LIST_ID} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{\n")
out.append("\t\t\tisa = XCConfigurationList;\n")
out.append("\t\t\tbuildConfigurations = (\n")
out.append(f"\t\t\t\t{TGT_DEBUG_ID} /* Debug */,\n")
out.append(f"\t\t\t\t{TGT_RELEASE_ID} /* Release */,\n")
out.append("\t\t\t);\n")
out.append("\t\t\tdefaultConfigurationIsVisible = 0;\n")
out.append("\t\t\tdefaultConfigurationName = Release;\n")
out.append("\t\t};\n")
out.append(section_footer("XCConfigurationList"))

out.append("\t};\n")
out.append(f"\trootObject = {PROJECT_ID} /* Project object */;\n")
out.append("}\n")

# Write the pbxproj
XCODEPROJ.mkdir(parents=True, exist_ok=True)
(XCODEPROJ / "project.pbxproj").write_text("".join(out))

# Write xcworkspace
workspace_dir = XCODEPROJ / "project.xcworkspace"
workspace_dir.mkdir(exist_ok=True)
(workspace_dir / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Workspace\n'
    '   version = "1.0">\n'
    '   <FileRef\n'
    '      location = "self:">\n'
    '   </FileRef>\n'
    '</Workspace>\n'
)

# Shared data: disable snapshot + wait for auto-create
shared = workspace_dir / "xcshareddata"
shared.mkdir(exist_ok=True)
(shared / "IDEWorkspaceChecks.plist").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n'
    '<dict>\n'
    '    <key>IDEDidComputeMac32BitWarning</key>\n'
    '    <true/>\n'
    '</dict>\n'
    '</plist>\n'
)

# Scheme
schemes_dir = XCODEPROJ / "xcshareddata" / "xcschemes"
schemes_dir.mkdir(parents=True, exist_ok=True)
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET_ID}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
(schemes_dir / f"{PROJECT_NAME}.xcscheme").write_text(scheme)

print(f"Wrote {XCODEPROJ}")
print(f"  {len(swift_files)} swift files")
print(f"  {len(asset_catalogs)} asset catalogs")
print(f"  {len(font_files)} font files")
print(f"  {len(json_files)} json resources")
