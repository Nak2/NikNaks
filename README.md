# NikNaks
 A library with various features for Gary's Mod I've created.
 It features a ByteBuffer, BSP Parser, NodeGraph, Navigation Mesh, PathFinding and more.
 
>***Note:** May not be reuploaded to workshop or any other Steam© services without specific prior written permission.<br>
See: https://github.com/Nak2/NikNaks/blob/main/LICENSE for more info.
### [ByteBuffer](https://github.com/Nak2/NikNaks/wiki/ByteBuffer)
------
ByteBuffers are simelar to file-objects as they store data in a 32-bit number-array.
* They offer speeds up to 80x faster than the regular file-IO system. As they skip the Lua -> C -> Lua header.
* Have additional features, structures and allows to be loaded entirly in memory.
* Can both Read and Write at the same time.

>***Note:** ByteBuffers have some limits, as reading and writing strings tent to be faster using the file-IO.
### [BSP Parser](https://github.com/Nak2/NikNaks/wiki/BSP-Parser)
-------------
BSP Parser allows you to read any Source-based maps Gary's Mod allow and retrive data and informations otherwise blocked off.
* Can read any BSP file form version 17 to 21.
* Holds map informations (Version, MapSize, IsCold, .. ect)
* Can List all map entities and their data.
* Can List all StaticProps and returns a Lua-structure with their information.
* Can list all Cubemaps, their positions and texture.
* Can list all textures used by the map.
* Can read any Lump-data.
* And more ...
### PathFinding
------
NikNaks comes two two valid types of PathFind-systems. Both returns the same LPathFollow object. Allowing your NPCs to choose between the two systems.
***Note:** These can only be loaded after `InitPostEntity`.
##### NodeGraph
A fast lua-based system to mimic, load, edit and patch Valves NodeGraphs ( AIN files ).
* Has all basic nodes ( Ground, Air, Climb, Hint .. ect)
* Uses a grid-system to speed up PathFinding.
* Can patch zones within the ain file.
* Has PathFinding and AsyncPathFinding.
* Allows multiple NodeGraphs to be loaded at the same time.
* And more ...
##### NNN
NikNaks own navigationmesh. Can be compiled from NAV + BSP -> NNN or manually created.
* Up to 99% less file-size than NAV.
* Uses a grid-system to speed up PathFinding.
* Supports hintpoints, move-points and other features.
* Supports air pathfinding, climbing, jump/jumpdown and more.
* Purely created in Lua for speed up pathfinding.
* Has AsyncPathFinding.
* And more ...
### Extended functions
----------------------
Has a list of extended and useful features.
* Color functions ( Luminance, Hex support, Brighten/Darken .. ect )
* ModelSize, ModelMaterial, AccessorFuncEx and more.
