module musictag.support;

import std.stdio : File;
import std.traits : isIntegral;
import std.typecons : Flag, Yes, No;



/// Decodes the supplied bytes into a native integer
/// assuming byte order given as parameter
T decodeInteger(T)(const(ubyte)[] data, Flag!"msbFirst" byteOrder)
if (isIntegral!T)
in { assert(data.length <= T.sizeof); }
body
{
    if (byteOrder == Yes.msbFirst)
        return decodeIntegerTplt!(T, Yes.msbFirst)(data);
    else return decodeIntegerTplt!(T, No.msbFirst)(data);
}

/// Decodes the supplied big-endian bytes into a native integer
T decodeBigEndian(T)(const(ubyte)[] data) if (isIntegral!T)
in { assert(data.length <= T.sizeof); }
body
{
    return decodeIntegerTplt!(T, Yes.msbFirst)(data);
}

/// Decodes the supplied little-endian bytes into a native integer
T decodeLittleEndian(T)(const(ubyte)[] data) if (isIntegral!T)
in { assert(data.length <= T.sizeof); }
body
{
    return decodeIntegerTplt!(T, No.msbFirst)(data);
}

private template decodeIntegerTplt(T, Flag!"msbFirst" byteOrder)
{
    T decodeIntegerTplt(const(ubyte)[] data)
    in { assert(data.length <= T.sizeof); }
    body
    {
        // Do not attempt a pointer cast here for native order
        // because we might have e.g. a sliced data.length == 2 for a uint.
        T res = 0;
        foreach (i, b; data)
        {
            immutable shift = 8 * (byteOrder == Yes.msbFirst ? (data.length - i - 1) : i);
            res |= b << shift;
        }
        return res;
    }
}


/// returns next power of 2 above the specified number
T nextPow2(T)(T x) if (isIntegral!T)
{
    import core.bitop : bsr;
	return x == 0 ? 1 : 1^^(bsr(x)+1);
}

/// Find pattern in File f, returning the offset where starts pattern
/// or -1 if pattern is not found.
size_t findInFile(File f, const(ubyte)[] pattern, size_t startOffset=-1)
{
    import std.algorithm : min, max;

    if (!f.isOpen) return -1;
    if (!pattern.length) return -1;

    immutable size_t bufSize = max(4096, nextPow2(pattern.length));
    auto buf = new ubyte[bufSize];
    if (startOffset != -1) f.seek(startOffset);
    auto done = cast(size_t)f.tell();
    size_t partial = 0;

mainFileLoop:
    foreach (chunk; f.byChunk(buf))
    {
        if (partial)
        {
            if (chunk[0 .. pattern.length-partial] == pattern[partial .. $])
                return done - partial;
            else
                partial = 0;
        }
        else
        {
        chunkLoop:
            foreach (i; 0 .. chunk.length)
            {
                size_t len = min(pattern.length, chunk.length-i);
                if (chunk[i .. i+len] == pattern[0 .. len])
                {
                    if (len < pattern.length)
                    {
                        partial = len;
                        break chunkLoop;
                    }
                    else return done + i;
                }
            }
        }
        done += chunk.length;
    }

    return -1;
}

version (unittest)
{
    void testFindPatternInFile(size_t pos, size_t filesize)
    {
        import std.format : format;
        import std.algorithm : max;
        import std.file : tempDir, write, remove;
        import std.path : chainPath;
        import std.conv : to;

        string deleteMe = chainPath(tempDir(), "musictag.support.findInFile.test").to!string;

        auto pattern = cast(immutable (ubyte)[])"PatternToBeFound";
        filesize = max(filesize, pos+pattern.length);

        auto content = new ubyte[filesize];
        content[pos .. pos+pattern.length] = pattern;

        write(deleteMe, content);
        scope(exit) remove(deleteMe);

        auto f = File(deleteMe, "rb");
        assert(
            findInFile(f, pattern) == pos,
            format("testFindPatternInFile(%s, %s)", pos, filesize)
        );
    }

    unittest
    {
        // chunk size is 4096 (unless pattern is bigger than that)
        testFindPatternInFile(1000, 1234);  // in first chunk
        testFindPatternInFile(5000, 6000);  // in second chunk
        testFindPatternInFile(4090, 6000);  // testing partial
        testFindPatternInFile(0, 1000);     // testing file starts with pattern
        testFindPatternInFile(1000, 1000);  // testing file ends with pattern
        testFindPatternInFile(0, 0);        // testing file only contains pattern
    }
}
