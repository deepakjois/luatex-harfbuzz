## Full BiDi text layout in LuaTeX using luaharfbuzz and luabidi
### Running the examples

The steps below should work on Linux and OS X. These steps could be adapted to work on Windows if you can get Harfbuzz and luaharfbuzz installed properly, which can be a bit tricky.

#### Step 1: Install LuaTeX
Make sure you have LuaTeX 1.0.0 or later installed and located on path. You can use [Tex Live], [MacTeX] or any other TeX distribution of your choice.

[TeX Live]: https://www.tug.org/texlive/
[MacTeX]: http://www.tug.org/mactex/

#### Step 2: Install Lua 5.2 and LuaRocks in a sandboxed environment
Apart from LuaTeX, You will also need a separate installation of Lua and LuaRocks to install and use the necessary packages. The Lua version needs to be the same as the one embedded inside LuaTeX, which is version 5.2 at the moment.

It is highly recommended that you install Lua 5.2 and LuaRocks in a sandboxed environment on your machine. [Hererocks] makes it dead simple to do, on all platforms.

[Hererocks]:https://github.com/mpeterv/hererocks

```
wget https://raw.githubusercontent.com/mpeterv/hererocks/latest/hererocks.py
hererocks lua52 -l5.2 -rlatest
source lua52/bin/activate
eval $(luarocks path)
```

#### Step 3: Install the dependencies from LuaRocks

```
luarocks install ufy luabidi luaucdn luaharfbuzz
```

#### Step 4: Run the examples using the script provided

```
$ ./run.sh doc.tex
```

This will invoke LuaTeX with the right flags.

### Viewing the code
Please check out [setup.lua](setup.lua)

### Sample PDFs
Check the [Samples folder](./samples).

#### _noto_urdu.tex_

![noto_urdu.pdf](img/noto_urdu.png)

#### _doc.tex_
![doc.pdf](img/doc.png)

### Reporting Bugs/Suggestions
If you encounter any issues or have any suggestions or questions, please [file an issue](https://github.com/deepakjois/luatex-harfbuzz/issues/new).
