## Full BiDi text layout in LuaTeX using luaharfbuzz and luabidi

_WARNING: This is pre-release code, and very much a work in progress._

### Running the examples

The steps below should work on Linux and OS X. These steps could be adapted to work on Windows if you can get Harfbuzz and luaharfbuzz installed properly, which can be a bit tricky.

#### Step 1: Install LuaTeX and Harfbuzz
* Make sure you have LuaTeX 1.0.0 or later installed and located on path. You can use [Tex Live], [MacTeX] or any other TeX distribution of your choice.

* Harfbuzz should be available in your operating system’s package manager. On OS X you can install it using `brew install harfbuzz`, and on Ubuntu using `apt-get install libharfbuzz0b libharfbuzz-dev`.

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
luarocks install ufylayout
```

#### Step 4: Run the examples using the script provided

```
$ ./run.sh doc.tex
```

This will invoke LuaTeX with the right flags.

### How it works
Please check out [hbtex.lua](hbtex.lua) for the callbacks, and [ufylayout] LuaRocks module for the layout code.

[ufylayout]: https://github.com/deepakjois/ufylayout

### Sample PDFs
Check the [Samples folder](./samples).

#### _noto_urdu.tex_

![noto_urdu.pdf](img/noto_urdu.png)

#### _doc.tex_
![doc.pdf](img/doc.png)

### Reporting Bugs/Suggestions
If you encounter any issues or have any suggestions or questions, please [file an issue](https://github.com/deepakjois/luatex-harfbuzz/issues/new).

### Credits

The BiDi and shaping code is adapted from [libraqm](https://github.com/HOST-Oman/libraqm).