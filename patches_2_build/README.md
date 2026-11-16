# Patches to build as stripped LV2 plugins

Put `.aqua` patch files here (made with Export Patch in the Aquanode Modular app), then build one by its name, without the `.aqua` ending:

```bash
./build_stripped.sh MyBass
```

The plugin gets the name of the patch: `MyBass.aqua` becomes `MyBass.lv2`. Use letters, digits, spaces, `-` and `_` in the file name. Add `--fx` for an effect.

`EchoTest.aqua` is a small test patch (oscillator → polyphony sum → delay → reverb → audio out), written by hand to try the build; it is not a patch from the app.

`VitaTest.aqua` is a second hand-written test patch: the Vita synth card wired to Audio Out, to try a stripped build with a built-in synth.
