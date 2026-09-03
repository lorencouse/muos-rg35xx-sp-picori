Third-party licences for the Project Picori PortMaster package
==============================================================

`tmc_pc` is one statically linked executable. Everything listed below is
compiled into it, so its licence travels with the binary.

  Component        Licence       File
  ---------------  ------------  --------------------------------
  Project Picori   GPL-3.0+      LICENSE-picori-GPL-3.0.txt
  SDL3 3.4.12      zlib          LICENSE-SDL3-zlib.txt
  Dear ImGui       MIT           LICENSE-DearImGui-MIT.txt
  nlohmann/json    MIT           LICENSE-nlohmann-json-MIT.txt
  fmt              MIT           LICENSE-fmt-MIT.txt
  GuiLite          Apache-2.0    LICENSE-GuiLite-Apache-2.0.txt
  agbplay (core)   see notice    NOTICE-agbplay.txt

Because the whole work is conveyed under the GPL-3.0-or-later, the
Corresponding Source is the tag it was built from:

  https://github.com/lorencouse/tmc/releases/tag/v0.8.3-sp4

which is a fork of https://github.com/999sian/tmc over the
https://github.com/zeldaret/tmc decompilation.

Linked dynamically against whatever the device provides, and therefore NOT
bundled here: libpng16, zlib, libEGL, libGLESv2, libgomp, and the C library.

gptokeyb2 is supplied by PortMaster itself and is not redistributed by this
port; its licence ships with PortMaster.

No game data is included. The player supplies their own ROM.
