module musictag.support;

import std.stdio : File;
import std.traits : isIntegral;
import std.typecons : Flag, Yes, No;
import std.range : isInputRange, ElementType;



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

/// Checks weither the supplied type conforms to ByteInputRange static interface,
/// that is InputRange of ubytes, a name property and a findPattern method that
/// seeks the data source to the next occurence of pattern or to the source exhaust
template isBytesInputRange(T)
{
    enum isBytesInputRange = isInputRange!T && is(ElementType!T == ubyte) &&
    is(typeof((T t, const(ubyte)[] pattern)
    {
        string n = t.name;
        ulong p = t.findPattern(pattern);
    }));
}


/// Checks weither T conforms to the BufBytesInputRange static interface
/// BufBytesInputRange implies isBytesInputRange and the presence of readBuf methods
/// that efficiently retrieves an array of bytes from the source
template isBufBytesInputRange(T)
{
    enum bool isBufBytesInputRange = isBytesInputRange!T && is(typeof(
    (T t)
    {
        ubyte[] buf1 = t.readBuf(new ubyte[10]);
        const(ubyte)[] buf2 = t.readBuf(10);
    }));
}


/// Read bytes from the supplied BytesInputRange to the supplied buffer
/// and return what could be read.
/// Takes advantage of BufBytesInputRange static interface if available.
ubyte[] readBytes(R)(ref R range, ubyte[] buf) if (isBufBytesInputRange!R)
{
    return range.readBuf(buf);
}

/// Ditto
ubyte[] readBytes(R)(ref R range, ubyte[] buf)
if (isBytesInputRange!R && !isBufBytesInputRange!R)
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


/// Read len bytes from the supplied ReadBufRange type and return what
/// could be read. Possibly returns a slice of the range internal buffer
/// if range internal buffer conforms to BufBytesInputRange and if enough
/// available bytes in the buffer. Otherwise, allocates and return a new
/// buffer. Returned buffer may be invalidated after next data fetch
/// from the range, and data should be duplicated if needed to be kept.
const(ubyte)[] readBytes(R)(ref R range, size_t len) if (isBufBytesInputRange!R)
{
    return range.readBuf(len);
}

/// Ditto
const(ubyte)[] readBytes(R)(ref R range, size_t len)
if (isInputRange!R && !isReadBytesRange!R)
{
    // return type const or not const?
    ubyte[] buf = new ubyte[len];
    return readBytes(range, buf);
}


static assert(isBytesInputRange!BufferedFileRange);
static assert(isBufBytesInputRange!BufferedFileRange);


/// Buffered file input range.
/// Implements BufBytesInputRange static interface.
/// Also provide size, seek and tell methods that shortcut
/// to the encapsulated File.
struct BufferedFileRange
{
    import std.stdio : SEEK_SET;

    /// Build a BufferedFileRange. Supplied file MUST be open beforehand.
    this(File file)
    in { assert(file.isOpen); }
    body
    {
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
            len = min(len, _file.size - _file.tell);

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

        size_t done = 0;
        do {
            immutable until = min(_slice.length, buf.length-done);
            buf[done .. done+until] = _slice[0 .. until];
            _slice = _slice[until .. $];
            done += until;
            if (!_slice.length) next();
        }
        while(done < buf.length && _slice.length != 0);
        return buf[0 .. done];
    }

    /// The file name.
    /// See std.stdio.File.size
    @property string name() const
    {
        return _file.name;
    }

    /// See std.stdio.File.size
    @property ulong size()
    {
        return _file.size;
    }

    /// See std.stdio.File.tell
    @property ulong tell() const
    {
        return _file.tell() - cast(ulong)_slice.length;
    }

    /// See std.stdio.File.seek
    /// Invalidate the internal buffer
    void seek(long pos, int origin=SEEK_SET)
    {
        _file.seek(pos, origin);
        _slice = [];
        next();
    }

    /// Seeks the file to the beginning of next occurence of pattern or to end of file.
    /// Returns the number of bytes advanced (0 indicates pattern was found at
    /// the current position).
    ulong findPattern(const(ubyte)[] pattern)
    {
        import std.algorithm : min;

        ulong adv = 0;
        size_t found = 0;
        bool fractionned;
        immutable origPos = tell();
        _pattern = [];

    mainFileLoop:
        while (!empty && found < pattern.length)
        {
            size_t done = 0;
            if (fractionned)
            {
                size_t until = min(_slice.length, pattern.length-found);
                if (_slice[0 .. until] == pattern[found .. found+until])
                {
                    found += until;
                    if (found < pattern.length) // exhausted a 2nd slice!
                    {
                        _slice = [];
                        next();
                    }
                }
                else
                {
                    // false alarm, we restart over with the current slice from its begin
                    done += found; // missing from previous loop
                    found = 0;
                    fractionned = false;
                    continue;
                }
            }
            else
            {
            chunkLoop:
                foreach (i; 0 .. _slice.length)
                {
                    size_t until = min(pattern.length, _slice.length-i);
                    if (_slice[i .. i+until] == pattern[0 .. until])
                    {
                        found = until;
                        fractionned = until < pattern.length;
                        done = i;
                        break chunkLoop;
                    }
                }
                if (!found)
                {
                    done = _slice.length;
                    _slice = [];
                    next();
                }
                else if (fractionned)
                {
                    _slice = [];
                    next();
                }
                else
                {
                    assert(found == pattern.length);
                    _slice = _slice[done .. $];
                }
            }
            adv += done;
        }
        if (fractionned)
        {
            // If pattern has been found fractionned over 2 (or more) slices,
            // then buffer cannot point on the pattern begin because was unvalidated.
            // We place back the file pointer at the begin of the pattern.
            _file.seek(origPos+adv, SEEK_SET);
            _slice = [];
            next();
        }
        return adv;
    }


private:

    void next()
    {
        assert(!_slice.length);
        _slice = _file.rawRead(_buffer);
    }

    enum bufSize = 4096;

    File _file;
    ubyte[] _pattern;
    ubyte[] _slice;
    ubyte[] _buffer;
}



version (unittest)
{
    void testFindPatternInBufferedFileRange(size_t pos, size_t filesize)
    {
        import std.format : format;
        import std.algorithm : max;
        import std.file : tempDir, write, remove;
        import std.path : chainPath;
        import std.conv : to;

        string deleteMe = chainPath(tempDir(), "musictag.support.BufferedFileRange.test").to!string;

        auto pattern = cast(immutable (ubyte)[])"PatternToBeFound";
        filesize = max(filesize, pos+pattern.length);

        {
            auto content = new ubyte[filesize];
            content[] = 'X';
            content[pos .. pos+pattern.length] = pattern;
            write(deleteMe, content);
        }

        scope(exit) remove(deleteMe);

        auto bfr = BufferedFileRange(File(deleteMe, "rb"));
        immutable adv = bfr.findPattern(pattern);
        assert(
            adv == pos,
            format("testFindPatternInBufferedFileRange(%s, %s) returned value", pos, filesize)
        );
        assert(!bfr.empty);
        auto start = bfr.readBuf(new ubyte[pattern.length]);
        assert(
            start == pattern,
            format("testFindPatternInBufferedFileRange(%s, %s) state", pos, filesize)
        );
    }

    unittest
    {
        // buffer size is 4096
        testFindPatternInBufferedFileRange(1000, 1234);  // in first chunk
        testFindPatternInBufferedFileRange(5000, 6000);  // in second chunk
        testFindPatternInBufferedFileRange(4090, 6000);  // testing partial
        testFindPatternInBufferedFileRange(0, 1000);     // testing file starts with pattern
        testFindPatternInBufferedFileRange(1000, 1000);  // testing file ends with pattern
        testFindPatternInBufferedFileRange(0, 0);        // testing file only contains pattern
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
