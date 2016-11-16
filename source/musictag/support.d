module musictag.support;

import std.stdio : File;
import std.traits : isIntegral;
import std.typecons : Flag, Yes, No;
import std.range : isInputRange;



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

/// Checks weither T conforms to the ReadBytesRange static interface
/// isReadBytesRange implies inInputRange and the presence of readBuf methods.
template isReadBytesRange(T)
{
    enum bool isReadBytesRange = isInputRange!T && is(typeof(
    (T t)
    {
        ubyte[] buf1 = t.readBuf(new ubyte[10]);
        const(ubyte)[] buf2 = t.readBuf(10);
    }));
}


/// Read len bytes from the supplied ReadBufRange type and return what
/// could be read.
const(ubyte)[] readBytes(R)(R range, size_t len) if (isReadBytesRange!R)
{
    return range.readBuf(len);
}


/// Read bytes from the supplied ReadBufRange to the supplied buffer
/// and return what could be read.
ubyte[] readBytes(R)(R range, ubyte[] buf) if (isReadBytesRange!R)
{
    return range.readBuf(buf);
}


/// Read len bytes from the supplied ReadBufRange type and return what
/// could be read.
const(ubyte)[] readBytes(R)(R range, size_t len)
if (isInputRange!R && !isReadBytesRange!R)
{
    // return type const or not const?
    ubyte[] buf = new ubyte[len];
    return readBytes(range, buf);
}


/// Read bytes from the supplied ReadBufRange to the supplied buffer
/// and return what could be read.
ubyte[] readBytes(R)(R range, ubyte[] buf)
if (isInputRange!R && !isReadBytesRange!R)
{
    size_t pos;
    while(pos < buf.length && !range.empty)
    {
        buf[pos] = range.front;
        pos++;
        range.popFront();
    }
    return buf[0 .. pos];
}


/// Buffer file input range.
/// also implement hasReadBuf static interface
struct BufferedFileRange
{
    import std.stdio : SEEK_END;

    /// Build a BufferedFileRange. Supplied file is requested to be open
    this(File file)
    in {
        assert(file.isOpen);
    }
    body {
        _file = file;
        _buffer = new ubyte[bufSize];
        next();
    }

    /// Implementation of InputRange
    @property bool empty()
    {
        return _slice.length == 0;
    }

    /// Ditto
    @property ubyte front()
    {
        return _slice[0];
    }

    /// Ditto
    void popFront()
    {
        _slice = _slice[1 .. $];
        if (!_slice.length) next();
    }

    /// Reads a len bytes from the file and returns what could
    /// actually be read.
    /// Attempt is made to return a slice to the internal buffer
    /// but allocates a new one if requested quantity is larger to
    /// what left to be read in internal the buffer.
    /// If slice to the internal buffer is returned, note that it
    /// will not be longer valid after call to popFront, readBuf or tell.
    /// If read data must be kept, the overload taking a user supplied buffer
    /// is a better option, because it avoids data duplication.
    const(ubyte)[] readBuf(size_t len)
    {
        if (len <= _slice.length)
        {
            auto res = _slice[0 .. len];
            _slice = _slice[len .. $];
            if (!_slice.length) next();
            return res;
        }
        else
        {
            import std.algorithm : min;

            // checking how much remains in the file
            immutable pos = _file.tell();
            _file.seek(0, SEEK_END);
            len = min(len, _file.tell() - pos);
            _file.seek(pos);

            // allocate and fill return buf
            return this.readBuf(new ubyte[len]);
        }
    }


    /// Read data from file and places it in the user supplied buffer.
    /// Returns a slice of the supplied buffer corresponding to what
    /// could actually be read.
    ubyte[] readBuf(ubyte[] buf)
    {
        import std.algorithm : min;

        size_t done;
        do {
            immutable todo = min(_slice.length, buf.length-done);
            buf[done .. done+todo] = _slice[0 .. todo];
            _slice = _slice[todo .. $];
            done += todo;
            if (!_slice.length) next();
        }
        while(done < buf.length && _slice.length != 0);
        return buf[0 .. done];
    }

private:

    void next()
    {
        assert(!_slice.length);
        _slice = _file.rawRead(_buffer);
    }

    enum bufSize = 4096;

    File _file;
    ubyte[] _slice;
    ubyte[] _buffer;
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
    string deleteMe;

    static this() {
        import std.file : tempDir;
        import std.path : chainPath;
        import std.conv : to;
        deleteMe = chainPath(tempDir(), "musictag.utils.test").to!string;
    }

    static ~this()
    {
        import std.file : remove, exists;
        if (exists(deleteMe)) remove(deleteMe);
    }

    void testFindPatternInFile(size_t pos, size_t filesize)
    {
        import std.format : format;
        import std.algorithm : max;
        import std.file : write, remove;

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
