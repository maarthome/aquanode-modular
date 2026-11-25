#!/usr/bin/env python3
"""Generate the build inputs for a stripped Aquanode Modular plugin.

A stripped plugin contains the engine and only the modules one patch uses. It has no
editor window and starts with that patch loaded. This script reads the patch, works out
which modules it uses, and writes a module registry naming only those, the embedded
patch, and a small CMake file, to a folder that stripped/CMakeLists.txt picks up.

Normally run by build_stripped.sh.
"""
import argparse, hashlib, io, os, re, sys, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JUCER = os.path.join(ROOT, "Aquanode_Modular.jucer")

# Always present: the engine minus Render to File (editor-only), and the module core.
ENGINE_SKIP = {"Source/Engine/PatchRender.cpp"}
ALWAYS_TYPES = {"io.audioIn", "io.audioOut"}
INIT_TYPES = {False: {"osc.basic", "util.polysum", "io.audioOut"},
              True: {"io.audioIn", "io.audioOut"}}
NO_PRESETS_STUBS = "stripped/NoPresetsStubs.cpp"
NO_PLUGINS_STUBS = "stripped/NoPluginsStubs.cpp"
DX7_PLUGIN = "virtualdx7"   # its code already contains the MTS client that MTS_CLIENT provides
PROCESSOR = "Source/Engine/PluginProcessor.cpp"
MTS_CLIENT = "Source/PluginSources/virtualdx7/Source/External/MTS-ESP/libMTSClient.cpp"

REGISTER = re.compile(r"^\s*AQUANODE_REGISTER_MODULE\s*\(\s*(\w+)\s*,", re.M)
DEFINE_PLUGIN = re.compile(r'^\s*AQP_DEFINE_PLUGIN\s*\(\s*(\w+)\s*,\s*"([^"]+)"', re.M)
# typeId = "fx.delay";  or, for the piano models,  makeDescriptor ("osc.piano", ...)
TYPE_LITERAL = re.compile(r'(?:typeId\s*=|makeDescriptor\s*\()\s*"([^"]+)"')
INCLUDE = re.compile(r'^\s*#\s*include\s+"([^"]+)"', re.M)


def die(msg):
    sys.exit("make_stripped: " + msg)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace") as f:
        return f.read()


def compiled_sources():
    text = open(JUCER, encoding="utf-8").read()
    out = []
    for tag in re.findall(r"<FILE [^>]*>", text):
        m = re.search(r' file="([^"]+)"', tag)
        if m and ' compile="1"' in tag:
            out.append(m.group(1))
    return out


def patch_types(path):
    """Module type names used by a patch file (.aqua zip or bare patch XML)."""
    data = open(path, "rb").read()
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = [n for n in z.namelist() if n.split("/")[-1] == "patch.xml"]
            if not names:
                die("no patch.xml inside " + path)
            xml = z.read(sorted(names, key=len)[0]).decode("utf-8", "replace")
    else:
        xml = data.decode("utf-8", "replace")
    if "<AquanodePatch" not in xml:
        die(path + " is not an Aquanode patch (export it from the app with Export Patch)")
    return set(re.findall(r'<Module\b[^>]*\btype="([^"]+)"', xml))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--name", help="plugin name shown in the host (default: the patch file's name)")
    ap.add_argument("--patch", help=".aqua file exported from the app (default: the Init patch)")
    ap.add_argument("--fx", action="store_true", help="build an effect instead of an instrument")
    ap.add_argument("--window", action="store_true", help="keep the editor window (larger plugin)")
    ap.add_argument("--gl", choices=["driver", "force33", "software"], default="driver",
                    help="OpenGL for the window: the driver as is, the driver told to offer 3.3, "
                         "or Mesa's software renderer")
    ap.add_argument("--out", required=True, help="specs folder; a sub-folder per plugin is written in it")
    args = ap.parse_args()

    if not args.name:
        # named after the patch it is made of
        stem = os.path.splitext(os.path.basename(args.patch))[0] if args.patch else "Aqua Init"
        args.name = re.sub(r"\s+", " ", re.sub(r"[^A-Za-z0-9 _-]", " ", stem)).strip()[:41]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 _-]{0,40}", args.name):
        die("the plugin name may only contain letters, digits, spaces, - and _ (max 41 characters); "
            "got '%s' - pass another one with --name" % args.name)
    slug = re.sub(r"[^a-z0-9]+", "-", args.name.lower()).strip("-")
    args.out = os.path.join(args.out, slug)

    sources = compiled_sources()
    module_files = [s for s in sources if s.startswith("Source/Modules/") and "/Core/" not in s]

    # Which file provides which module type, and which classes each file registers.
    provides, classes = {}, {}
    for f in module_files:
        text = read(f)
        classes[f] = REGISTER.findall(text)
        if classes[f]:
            for t in TYPE_LITERAL.findall(text):
                provides.setdefault(t, f)

    # The built-in synths and effects (Vita, the DX7, ...): plugin id -> the class of its
    # card. One reference to that class brings in the plugin's whole object file, and
    # with it the card ("plugin.<id>") and its patch modules ("plugin.<id>.<kind>").
    plugin_class = {}
    for f in sources:
        if f.startswith("Source/Plugins/") and not f.startswith("Source/Plugins/Host/"):
            for cls, pid in DEFINE_PLUGIN.findall(read(f)):
                plugin_class[pid] = cls

    wanted = set(ALWAYS_TYPES)
    wanted |= patch_types(args.patch) if args.patch else INIT_TYPES[args.fx]
    if args.window:
        wanted |= INIT_TYPES[args.fx]   # the window's Initialize Patch button builds this patch

    plugins_used = set()
    for t in wanted:
        if t.startswith("plugin.") and t not in provides:
            pid = t.split(".")[1]
            if pid in plugin_class:
                plugins_used.add(pid)

    def supported(t):
        return t in provides or (t.startswith("plugin.") and t.split(".")[1] in plugins_used)

    unknown = sorted(t for t in wanted if not supported(t))
    if unknown:
        die("these module types are not supported in stripped builds yet:\n  " + "\n  ".join(unknown))

    chosen = {provides[t] for t in wanted if t in provides}

    engine = [s for s in sources if s.startswith("Source/Engine/") and s not in ENGINE_SKIP and s != PROCESSOR]
    core = ["Source/Modules/Core/ModuleCore.cpp"]
    # Only the engine is compiled for a stripped plugin. The module code comes out of the
    # library of the full build: the registry below names the wanted modules, and the
    # linker takes just those modules, and whatever they in turn need, from that library.
    all_sources = engine + core
    if DX7_PLUGIN not in plugins_used:
        all_sources.append(MTS_CLIENT)
    if args.window:
        all_sources.append(NO_PRESETS_STUBS)
        if not plugins_used:
            all_sources.append(NO_PLUGINS_STUBS)

    reg_classes = sorted({c for f in chosen for c in classes[f]} | {plugin_class[p] for p in plugins_used})

    os.makedirs(args.out, exist_ok=True)

    def write(name, text):
        path = os.path.join(args.out, name)
        if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
            open(path, "w", encoding="utf-8").write(text)

    # 1. the registry: same job as Modules/Core/ModuleRegistry.cpp, for the chosen modules only
    decl = "".join('extern "C" bool %s_aqRegistered;\n' % c for c in reg_classes)
    touch = "".join("    sink = sink ^ %s_aqRegistered;\n" % c for c in reg_classes)
    write("StrippedRegistry.cpp",
          "// Generated by tools/make_stripped.py - do not edit.\n"
          "namespace aquanode { int forceLinkAllModules(); }\n\n" + decl +
          "\nint aquanode::forceLinkAllModules()\n{\n    volatile bool sink = false;\n" + touch +
          "    return sink ? 1 : 0;\n}\n")

    # 2. the processor of the stripped plugin: no editor, and the start patch loaded
    if args.patch:
        data = open(args.patch, "rb").read()
        rows = ",\n".join("    " + ",".join(str(b) for b in data[i:i + 24]) for i in range(0, len(data), 24))
        load = ("static const unsigned char patchData[] = {\n" + rows + "\n};\n\n"
                "static void loadStartPatch (AquanodeModularAudioProcessor& p)\n{\n"
                "    juce::MemoryInputStream in (patchData, sizeof (patchData), false);\n"
                "    if (! p.importPatchFromStream (in, \"%s\"))\n        p.initializePatch();\n}\n" % args.name)
    else:
        load = ("static void loadStartPatch (AquanodeModularAudioProcessor& p)\n{\n"
                "    p.initializePatch();\n}\n")
    gl = {"driver": "",
          "force33": '    setenv ("MESA_GL_VERSION_OVERRIDE", "3.3", 0);\n'
                     '    setenv ("MESA_GLSL_VERSION_OVERRIDE", "330", 0);\n',
          "software": '    setenv ("LIBGL_ALWAYS_SOFTWARE", "1", 0);\n'}[args.gl]
    if gl:
        gl = ("// OpenGL setting for the window (build_stripped.sh --gl %s). Set when the plugin is\n"
              "// loaded, before any window exists, so Mesa sees it when the context is made.\n"
              "#include <cstdlib>\n"
              "static const bool glEnvironmentSet = []\n{\n%s    return true;\n}();\n\n") % (args.gl, gl)
    write("StrippedStart.cpp",
          "// Generated by tools/make_stripped.py - do not edit.\n"
          '#include "Source/Engine/PluginProcessor.h"\n\n' + gl + load + """
namespace
{
    struct StrippedProcessor final : AquanodeModularAudioProcessor
    {
        StrippedProcessor()
        {
            loadStartPatch (*this);
            uiSidebarVisible = false;   // the patch is fixed: start with the module list closed
        }
%s    };
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new StrippedProcessor();
}
""" % ("" if args.window else
       "        bool hasEditor() const override                      { return false; }\n"
       "        juce::AudioProcessorEditor* createEditor() override  { return nullptr; }\n"))

    # 3. PluginProcessor.cpp without the two things a stripped plugin must not have: the
    #    editor (it would drag in every module) and the full plugin's createPluginFilter.
    #    A changed copy is compiled, so the original file stays as upstream wrote it.
    text = read(PROCESSOR)
    edits = [("juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()", "static juce::AudioProcessor* unusedFullCreatePluginFilter()")]
    if not args.window:
        edits.append(("    return new AquanodeModularAudioProcessorEditor (*this);", "    return nullptr;   // stripped: no editor"))
    for old, new in edits:
        if text.count(old) != 1:
            die("%s changed upstream: expected exactly one '%s'. tools/make_stripped.py needs updating." % (PROCESSOR, old.strip()))
        text = text.replace(old, new)
    write("StrippedPluginProcessor.cpp",
          "// Generated by tools/make_stripped.py from %s - do not edit.\n" % PROCESSOR + text)

    # 4. what CMake needs to know
    digest = hashlib.sha1(slug.encode()).digest()
    letters = "abcdefghijklmnopqrstuvwxyz"
    code = "S" + "".join(letters[b % 26] for b in digest[:3])
    write("stripped.cmake",
          "# Generated by tools/make_stripped.py - do not edit.\n"
          'set(AQS_NAME "%s")\nset(AQS_SLUG "%s")\nset(AQS_CODE "%s")\nset(AQS_IS_FX %s)\n'
          "set(AQS_SOURCES\n%s)\n"
          % (args.name, slug, code, "TRUE" if args.fx else "FALSE",
             "".join('    "%s"\n' % s for s in all_sources)))

    write("name.txt", args.name + "\n")
    print("Stripped plugin '%s' (%s, %s%s)" % (args.name, "effect" if args.fx else "instrument",
                                               "window showing the patch" if args.window else "no window",
                                               ", OpenGL " + args.gl if args.window and args.gl != "driver" else ""))
    print("  module types : " + ", ".join(sorted(wanted)))
    if plugins_used:
        print("  built-in     : " + ", ".join(sorted(plugins_used)))
    print("  modules kept : %d building blocks of %d, %d built-in plugins of %d"
          % (len(reg_classes) - len(plugins_used), sum(len(c) for c in classes.values()),
             len(plugins_used), len(plugin_class)))


if __name__ == "__main__":
    main()
