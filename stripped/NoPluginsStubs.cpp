// Stripped plugins with a window whose patch uses none of the built-in synths and effects
// (Vita, the DX7, ...): an empty stand-in for the catalogue of those plugins.
//
// The editor calls these functions; the real ones are in
// Source/Plugins/Host/PluginCatalog.cpp. With "there are no plugins" defined here, that
// file and what hangs off it stay out, and the sidebar's Plugins section is empty.
// A patch that does use a built-in plugin gets the real catalogue instead of this file.

#include <JuceHeader.h>
#include "Source/Plugins/Host/PluginCatalog.h"

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
