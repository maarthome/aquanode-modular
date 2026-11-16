// Stripped plugins with a window (see ../build_stripped.sh): empty stand-ins for the
// parts of the app that exist to ADD things to a patch - the preset generators, the
// Quick-Add effects and the catalogue of built-in plugins.
//
// The editor calls these few functions. In the full app they sit in Source/Presets and
// Source/Plugins/Host/PluginCatalog.cpp, which refer to dozens of modules and synths.
// Defining them here, as "there is nothing to add", keeps all of that out of the plugin:
// the window shows the patch and its knobs, and the Random Preset, Quick-Add and Plugins
// sections are empty.

#include <JuceHeader.h>
#include "Source/Presets/PresetGenerators.h"
#include "Source/Presets/EffectAdders.h"
#include "Source/Plugins/Host/PluginCatalog.h"

namespace aquanode::presets
{
    const std::vector<Generator>& generators()                      { static const std::vector<Generator> none; return none; }
    const Generator* findGenerator (const juce::String&)            { return nullptr; }
    const std::vector<EffectAdder>& effectAdders()                  { static const std::vector<EffectAdder> none; return none; }
    const EffectAdder* findEffectAdder (const juce::String&)        { return nullptr; }
}

namespace aquanode::plugins
{
    std::vector<CatalogEntry>& catalog()                            { static std::vector<CatalogEntry> none; return none; }
    CatalogEntry* findEntry (const juce::String&)                   { return nullptr; }
    bool registerAudioAccess (const juce::String&, AudioAccess)     { return false; }
    const AudioAccess* audioAccessFor (const juce::String&)         { return nullptr; }
    int addGuiVersion (AquanodeModularAudioProcessor&, const juce::String&, juce::Point<int>)                  { return -1; }
    juce::String addPatchVersion (AquanodeModularAudioProcessor&, const juce::String&, const juce::File&, bool) { return {}; }
    juce::String convertGuiToPatch (AquanodeModularAudioProcessor&, int)                                       { return {}; }
    int openHeldPresetInPlugin (AquanodeModularAudioProcessor&, int)                                           { return -1; }
}
