// Stripped plugins with a window (see ../build_stripped.sh): empty stand-ins for the
// parts of the app that exist to ADD ready-made things to a patch - the preset generators
// and the Quick-Add effects.
//
// The editor calls these functions. In the full app they sit in Source/Presets, which
// refers to dozens of modules and synths. Defining them here, as "there is nothing to
// add", keeps all of that out of the plugin: the window shows the patch and its knobs,
// and the Random Preset and Quick-Add sections are empty.

#include <JuceHeader.h>
#include "Source/Presets/PresetGenerators.h"
#include "Source/Presets/EffectAdders.h"

namespace aquanode::presets
{
    const std::vector<Generator>& generators()                      { static const std::vector<Generator> none; return none; }
    const Generator* findGenerator (const juce::String&)            { return nullptr; }
    const std::vector<EffectAdder>& effectAdders()                  { static const std::vector<EffectAdder> none; return none; }
    const EffectAdder* findEffectAdder (const juce::String&)        { return nullptr; }
    void setQuickAddAnchor (int)                                    {}
}
