![alt text][banner]

 A library with various features for Garry's Mod I've created.
 It features an adv BitBuffer, BSP Parser, BSP Objects , PVS/PAS, and more.
 
>***Note:** May not be reuploaded to workshop or any other Steam© services without specific prior written permission.<br>
See: https://github.com/Nak2/NikNaks/blob/main/LICENSE for more info.
### [BitBuffer](https://github.com/Nak2/NikNaks/wiki/BitBuffer)
------
BitBuffers are simelar to file-objects as they store data in a 32-bit number-array.
* They offer speeds up to 80x faster than the regular file-IO system. As they skip the Lua -> C -> Lua header.
* Little/Big Endian support
* Allows for non-byte integers
* Supports Float / Dobule.
* Have additional features, structures and allows to be loaded entirely in memory.
* Can both Read and Write at the same time.

>***Note:** BitBuffers have some limits, as reading and writing strings tent to be faster using the file-IO.
### [BSP Parser](https://github.com/Nak2/NikNaks/wiki/BSP-Parser)
-------------
BSP Parser allows you to read any Source-based maps Garry's Mod allow and retrive data and informations otherwise blocked off.
* Can read any BSP file form version 17 to 21.
* Can read all Entity information.
* Allows to parse faces, leafs, PVS, PAS, StaticProps .. and so much more.

### DateTime / TimeDelta
An easy way to parse and handle time.
- Allows to retrieve the local timezone and/or DayLightSavings-time.
- Can parse strings to a unix-time and reverse.
- Can return the months, check for leapyears and more ..

### NodeGraph
A fast lua-based system to mimic, load, edit and patch Valves NodeGraphs ( AIN files ).
* Has all basic nodes ( Ground, Air, Climb, Hint .. ect)
* Uses a grid-system to speed up PathFinding.
* Can patch zones within the ain file.
* Has PathFinding and AsyncPathFinding.
* Allows multiple NodeGraphs to be loaded at the same time.
* And more ...

### Extended functions
----------------------
Has a list of extended and useful features.
* Color functions ( Luminance, Hex support, Brighten/Darken .. ect )
* ModelSize, ModelMaterial, AccessorFuncEx and more.

[banner]: https://github.com/Nak2/NikNaks/blob/main/assets/banner.png "NikNaks Banner"
