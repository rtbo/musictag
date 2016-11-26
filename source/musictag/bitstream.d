/// This module provides primitives to read data from data streams
/// (File or network). Primitives range from static interfaces that determine
/// capabilities of stream at compile time to functions that read data
/// out of a stream in an expected binary format (integers, strings, ...).
/// Is also provided utilities that allows reading integers on a bit by bit
/// basis.
/// Due to nature of IO data streams, mainly only input ranges are supported.
/// In addition, some streams may provide a Seekable interface, from which
/// other utilities can take advantage.
module musictag.bitstream;

import std.stdio : File;
import std.range : isInputRange, ElementType;
import std.traits : isIntegral, Unqual;
import std.exception : enforce;
import std.typecons : Flag, Yes, No;
import std.range.primitives;


/// Checks weither T conforms to ByteChunkRange static interface,
/// which is an input range of byte chunks (aka ubyte[])
enum isByteChunkRange(T) =  isInputRange!T &&
                            is(Unqual!(ElementType!T) == ubyte[]);

/// Checks weither something is an input range of bytes
enum isByteRange(T) = isInputRange!T && is(Unqual!(ElementType!T) == ubyte);

/// Checks weither something has method readBuf.
enum hasReadBuf(T) = is(typeof((T t) {
    ubyte[] data1 = t.readBuf(new ubyte[4]);
}));

/// Checks weither something has method seek and property tell.
enum isSeekable(T) = is(typeof((T t) {
    import std.stdio : SEEK_CUR;
    ulong pos = t.tell();
    t.seek(4);
    t.seek(4, SEEK_CUR);
}));

/// Checks weither something has a name property
enum hasName(T) = is(typeof((T t) {
    string n = t.name;
}));


static assert(isByteRange!(ubyte[]));
static assert(isByteRange!(const(ubyte)[]));

/// Builds a byte range with the supplied file.
/// bufSize is the internal buffer size that will be used
/// by the byte range.
/// The returned range has following capabilities:
///  - isByteRange
///  - hasReadBuf
///  - isSeekable
///  - hasLength
///  - hasName
auto byteRange(File file, size_t bufSize=FileByteRange.defaultBufSize)
{
    return FileByteRange(file, bufSize);
}

/// Builds a byte range with the supplied generic byte chunk range.
/// The returned range has following capabilities:
///  - isByteRange
///  - hasReadBuf
auto byteRange(R)(R range)
if (isByteChunkRange!R)
{
    return ByteRange!R(range);
}



// READING FUNCTIONS

// TODO:    check design of reader function that returns the range
//          to give chaining possibility


// raw bytes reading

/// Read bytes from the supplied ByteRange to the supplied buffer
/// and return what could be read.
/// Takes advantage of readBuf method if available.
ubyte[] readBytes(R)(ref R range, ubyte[] buf)
if (isByteRange!R && hasReadBuf!R)
{
    return range.readBuf(buf);
}

/// Ditto
ubyte[] readBytes(R)(ref R range, ubyte[] buf)
if (isByteRange!R && !hasReadBuf!R)
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


/// Convenience function that advances the range by the one returned byte.
ubyte readByte(R)(ref R range) if (isByteRange!R)
in { assert(!range.empty); }
body
{
    immutable res = range.front;
    range.popFront();
    return res;
}

// Integer reading

/// Reads from the supplied data source an integer encoded according byteOrder
/// over numBytes bytes.
T readInteger(T, R)(ref R range, Flag!"msbFirst" byteOrder, in size_t numBytes=T.sizeof)
if (isIntegral!T && isByteRange!R)
{
    if (byteOrder == Yes.msbFirst)
        return readIntegerTplt!(T, R, Yes.msbFirst)(range, numBytes);
    else return readIntegerTplt!(T, R, No.msbFirst)(range, numBytes);
}

/// Reads from the supplied data source an integer encoded in little endian
/// over numBytes bytes.
T readLittleEndian(T, R)(ref R range, in size_t numBytes=T.sizeof)
{
    return readIntegerTplt!(T, R, No.msbFirst)(range, numBytes);
}

/// Reads from the supplied data source an integer encoded in big endian
/// over numBytes bytes.
T readBigEndian(T, R)(ref R range, in size_t numBytes=T.sizeof)
{
    return readIntegerTplt!(T, R, Yes.msbFirst)(range, numBytes);
}

// having byteOrder known at compile time should make the compiler life easier
// during optimization
private template readIntegerTplt(T, R, Flag!"msbFirst" byteOrder)
{
    T readIntegerTplt(ref R range, in size_t numBytes)
    in { assert(numBytes <= T.sizeof); }
    body
    {
        T res = 0;
        foreach (i; 0 .. numBytes)
        {
            enforce(!range.empty);
            immutable shift = 8 * (
                byteOrder == Yes.msbFirst ? (numBytes - i - 1) : i
            );
            res |= T(range.front) << shift;
            range.popFront();
        }
        return res;
    }
}


unittest {
    import std.range : iota;
    import std.array : array;

    immutable(ubyte)[] pattern = iota(ubyte(16)).array().idup;

    auto data = pattern.dup;
    assert(data.readBigEndian!uint() == 0x00010203);
    assert(data.readLittleEndian!uint(3) == 0x060504);
    assert(data.readByte() == 0x07);
    assert(data.length == 8);
    assert(data.readBigEndian!ulong() == 0x08090a0b_0c0d0e0f);
    assert(data.empty);

    data = pattern.dup;
    auto bytes = data.readBytes(new ubyte[pattern.length]);
    assert(data.length == 0);
    assert(bytes == pattern);
}


// String reading


/// Reads len bytes out of the range and convert to utf-8.
/// Do not check for valid unicode.
string readStringUtf8(R)(ref R range, size_t len) if (isByteRange!R)
{
    import std.exception : assumeUnique;
    return cast(string)(assumeUnique(readBytes(range, new ubyte[len])));
}

/// Reads a utf-8 string until a null character is found or
/// until range exhausts. Do not check for valid unicode.
string readStringUtf8(R)(ref R range) if (isByteRange!R)
{
    import std.exception : assumeUnique;
    char[] res;
    while(!range.empty && range.front != 0)
    {
        res ~= range.front;
        range.popFront();
    }

    if (!range.empty) range.popFront(); // eat null

    return assumeUnique(res);
}


/// Reads len bytes from range and transcode them from latin-1 to utf-8.
/// Do not check for valid unicode.
string readStringLatin1(R)(ref R range, size_t len) if (isByteRange)
{
    import std.utf : encode;

    string res;
    char[4] buf = void;
    auto bytes = range.readBytes(new char[len]);

    foreach (dchar c; bytes) // latin-1 is unicode code points from 0 to 255
    {
        immutable len = encode(buf, c);
        res ~= buf[0 .. len];
    }

    return res;
}

/// Reads bytes from range and transcode them from latin-1 to utf-8
/// until a null character is found. Do not check for valid unicode.
string readStringLatin1(R)(ref R range) if (isByteRange!R)
{
    import std.utf : encode;

    string res;
    char[4] buf = void;

    while(!range.empty && range.front != 0)
    {
        immutable len = encode(buf, dchar(range.front));
        res ~= buf[0 .. len];
        range.popFront();
    }

    if (!range.empty) range.popFront(); // eat null

    return res;
}


private {
    // BOM is always read big endian from the data source.
    // Therefore a BOM in natural order indicates big endian
    // whatever the processor endianness.
    enum wchar beBom = 0xfeff;
    enum wchar leBom = 0xfffe;

}

/// Reads len bytes from range and transcode them from UTF16 with BOM to utf-8.
/// Attempts to read up to len bytes and stop if the range exhausts
/// Throws if the 2 first bytes are not a BOM.
/// Do not check for valid unicode.
string readStringUtf16Bom(R)(ref R range, size_t len) if (isByteRange!R)
{
    auto bom = bytes.readBigEndian!wchar();

    if (bom == beBom)
        return range.readUtf16Tplt!(Yes.msbFirst, No.stopsAtNull)(len);
    else if (bom == leBom)
        return range.readUtf16Tplt!(No.msbFirst, No.stopsAtNull)(len);
    else
    {
        import std.format : format;
        throw new Exception(format("not a BOM: 0x%x", bom));
    }
}

/// Reads bytes from range and transcode them from UTF16 with BOM to utf-8.
/// Attempts to read until a null char is found or the range exhausts.
/// Throws if the 2 first bytes are not a BOM.
/// Do not check for valid unicode.
string readStringUtf16Bom(R)(ref R range) if (isByteRange!R)
{
    auto bom = range.readBigEndian!wchar();

    if (bom == beBom)
        return range.readUtf16Tplt!(Yes.msbFirst, Yes.stopsAtNull)(-1);
    else if (bom == leBom)
        return range.readUtf16Tplt!(No.msbFirst, Yes.stopsAtNull)(-1);
    else
    {
        import std.format : format;
        throw new Exception(format("not a BOM: 0x%x", bom));
    }
}


/// Reads len bytes from range and transcode them from UTF16 BE to utf-8.
/// Attempts to read up to len bytes and stop if the range exhausts
/// Do not check for valid unicode.
string readStringUtf16BE(R)(ref R range, size_t len) if (isByteRange!R)
{
    return range.readUtf16Tplt!(Yes.msbFirst, No.stopsAtNull)(len);
}

/// Reads len bytes from range and transcode them from UTF16 LE to utf-8.
/// Attempts to read up to len bytes and stop if the range exhausts
/// Do not check for valid unicode.
string readStringUtf16LE(R)(ref R range, size_t len) if (isByteRange!R)
{
    return range.readUtf16Tplt!(No.msbFirst, No.stopsAtNull)(len);
}

/// Reads bytes from range and transcode them from UTF16 BE to utf-8.
/// Attempts to read until a null char is found or the range exhausts.
/// Do not check for valid unicode.
string readStringUtf16BE(R)(ref R range) if (isByteRange!R)
{
    return range.readUtf16Tplt!(Yes.msbFirst, Yes.stopsAtNull)(-1);
}

/// Reads bytes from range and transcode them from UTF16 LE to utf-8.
/// Attempts to read until a null char is found or the range exhausts.
/// Do not check for valid unicode.
string readStringUtf16LE(R)(ref R range) if (isByteRange!R)
{
    return range.readUtf16Tplt!(No.msbFirst, Yes.stopsAtNull)(-1);
}


private template readUtf16Tplt( Flag!"msbFirst" byteOrder,
                                Flag!"stopsAtNull" stopsAtNull)
{
    string readUtf16Tplt(R)(ref R range, size_t len)
    {
        import std.uni : isSurrogateHi;
        import std.utf : decodeFront, encode;

        string res;
        char[4] buf = void;
        wchar[2] wbuf;

        while(!range.empty && len-- != 0)
        {
            size_t units=1;
            wbuf[0] = range.readIntegerTplt!(wchar, R, byteOrder)(2);
            if (stopsAtNull == Yes.stopsAtNull && wbuf[0] == 0) break;
            if (isSurrogateHi(wbuf[0]))
            {
                enforce(!range.empty);
                wbuf[1] = range.readIntegerTplt!(wchar, R, byteOrder)(2);
                ++units;
            }

            auto wc = wbuf[0 .. units];
            immutable dchar c = decodeFront(wc);
            assert(!wc.length);
            immutable l8 = encode(buf, c);
            res ~= buf[0 .. l8];
        }
        return res;
    }
}




/// Finds a pattern in the given range and passes it.
/// Advances the range to the 1st byte passed the pattern and returns
/// the total number of bytes advanced (including the pattern).
/// The range is empty after that call if the pattern is not found
/// or if the pattern are the last byte of the range.
/// The version accepting a bool ref can be used disambiguate this
/// situation.
ulong eatPattern(R, P)(ref R range, P pattern)
if (isByteRange!R && isForwardRange!P && is(Unqual!(ElementType!P) == ubyte))
{
    ulong adv;
    const(ubyte)[] p = pattern.save;
    while(p.length != 0 && !range.empty)
    {
        if (p[0] == range.front) p.popFront();
        else p = pattern.save;

        range.popFront();
        ++adv;
    }
    return adv;
}

/// Ditto
ulong eatPattern(R, P)(ref R range, P pattern, out bool found)
if (isByteRange!R && isForwardRange!P && is(Unqual!(ElementType!P) == ubyte))
{
    ulong adv;
    auto p = pattern.save;
    while(!range.empty && !p.empty)
    {
        if (p[0] == range.front) p.popFront();
        else p = pattern.save;

        range.popFront();
        ++adv;
    }
    found = p.empty;
    return adv;
}



version (unittest)
{
    void testEatPatternInFileByteRange(in size_t pos, size_t filesize)
    {
        import std.format : format;
        import std.algorithm : max;
        import std.file : tempDir, write, remove;
        import std.path : chainPath;
        import std.conv : to;

        string deleteMe = chainPath(tempDir(), "musictag.support.eatPattern.test").to!string;

        auto pattern = cast(immutable (ubyte)[])"PatternToBeFound";
        filesize = max(filesize, pos+pattern.length);

        {
            auto content = new ubyte[filesize];
            content[] = 'X';
            content[pos .. pos+pattern.length] = pattern;
            write(deleteMe, content);
        }

        scope(exit) remove(deleteMe);

        auto br = byteRange(File(deleteMe, "rb"));
        immutable adv = br.eatPattern(pattern);
        assert(
            adv == pos+pattern.length,
            format("testEatPatternInFileByteRange(%s, %s) returned value", pos, filesize)
        );
        if (filesize == pos+pattern.length) assert(br.empty);
        else assert(!br.empty);
    }

    unittest
    {
        static assert (FileByteRange.defaultBufSize == 4096);

        testEatPatternInFileByteRange(1000, 1234);  // in first chunk
        testEatPatternInFileByteRange(5000, 6000);  // in second chunk
        testEatPatternInFileByteRange(4090, 6000);  // testing partial
        testEatPatternInFileByteRange(0, 1000);     // testing file starts with pattern
        testEatPatternInFileByteRange(1000, 1000);  // testing file ends with pattern
        testEatPatternInFileByteRange(0, 0);        // testing file only contains pattern
    }
}


// Byte Range implementations


// only for static assertions
private alias FileByChunk = typeof(File("f", "rb").byChunk(4));
static assert(isByteChunkRange!FileByChunk);


static assert(isByteRange!FileByteRange);
static assert(hasReadBuf!FileByteRange);
static assert(isSeekable!FileByteRange);
static assert(hasLength!FileByteRange);
static assert(hasName!FileByteRange);

/// A byte range encapsulating a file. Provides:
///  - isByteRange
///  - hasReadBuf
///  - isSeekable
///  - hasLength
///  - hasName
struct FileByteRange
{
    import std.stdio : SEEK_SET;

    /// default internal buffer size
    enum defaultBufSize = 4096;

    /// Build a FileByteStream
    this(File file, size_t bufSize=defaultBufSize)
    {
        this(file, new ubyte[bufSize]);
    }

    ///
    this(File file, ubyte[] buffer)
    in {
        assert(buffer.length > 0);
    }
    body {
        _file = file;
        _buffer = buffer;
        prime();
    }

    /// Implementation of InputRange
    @property bool empty()
    {
        return _chunk.length == 0;
    }

    /// Ditto
    @property ubyte front()
    {
        return _chunk[0];
    }

    /// Ditto
    void popFront()
    {
        _chunk = _chunk[1 .. $];
        if (!_chunk.length) prime();
    }


    /// Read data from file and places it in the supplied buffer.
    /// Returns a slice of the supplied buffer corresponding to what
    /// could actually be read.
    ubyte[] readBuf(ubyte[] buf)
    {
        import std.algorithm : min;

        size_t done = 0;
        do {
            immutable until = min(_chunk.length, buf.length-done);
            buf[done .. done+until] = _chunk[0 .. until];
            _chunk = _chunk[until .. $];
            done += until;
            if (!_chunk.length) prime();
        }
        while(done < buf.length && _chunk.length != 0);
        return buf[0 .. done];
    }

    /// How many bytes remain
    @property ulong length()
    {
        return size - tell;
    }

    /// The file name.
    /// See std.stdio.File.name
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
        return _file.tell() - cast(ulong)_chunk.length;
    }

    /// See std.stdio.File.seek
    /// Invalidate the internal buffer
    void seek(long pos, int origin=SEEK_SET)
    {
        _file.seek(pos, origin);
        _chunk = [];
        prime();
    }

private:

    void prime()
    {
        _chunk = _file.rawRead(_buffer);
        if (_chunk.length == 0) _file.detach();
    }

    File _file;
    ubyte[] _chunk;
    ubyte[] _buffer;
}


static assert(isByteRange!(ByteRange!FileByChunk));
static assert(hasReadBuf!(ByteRange!FileByChunk));
static assert(!isSeekable!(ByteRange!FileByChunk));
static assert(!hasLength!(ByteRange!FileByChunk));
static assert(!hasName!(ByteRange!FileByChunk));


/// A byte range adapter for a byte chunk range. Provides:
///  - isByteRange
///  - hasReadBuf
struct ByteRange(R) if (isByteChunkRange!R)
{
    this(R source)
    {
        _source = source;
        if (!_source.empty) _chunk = _source.front;
    }

    /// Implementation of input range interface
    @property bool empty()
    {
        return _chunk.length == 0 && _source.empty;
    }

    /// Ditto
    @property auto front()
    {
        return _chunk[0];
    }

    /// Ditto
    void popFront()
    {
        _chunk = _chunk[1 .. $];
        if (_chunk.length == 0)
        {
            _source.popFront();
            if (!_source.empty) _chunk = _source.front;
        }
    }

    /// Read data and places it in the supplied buffer.
    /// Returns a slice of the supplied buffer corresponding to what
    /// could actually be read.
    ubyte[] readBuf(ubyte[] buf)
    {
        import std.algorithm : min;

        size_t done = 0;
        do {
            immutable until = min(_chunk.length, buf.length-done);
            buf[done .. done+until] = _chunk[0 .. until];
            _chunk = _chunk[until .. $];
            done += until;
            if (!_chunk.length)
            {
                _source.popFront();
                if (!_source.empty) _chunk = _source.front;
            }
        }
        while(done < buf.length && _chunk.length != 0);
        return buf[0 .. done];
    }

private:

    alias Chunk = ElementType!R;

    R _source;
    Chunk _chunk;
}


// Bit by bit range

auto bitRange(R)(ref R source) if (isByteRange!R)
{
    return BitRange!R(source);
}


private struct BitRange(R)
{
    this(ref R source)
    {
        _source = &source;
    }

    ~this()
    {
        assert(_consumedBits == 0, "BitRange dropped in an uneven state");
    }

    invariant
    {
        assert(_consumedBits <= 8);
    }

    @property bool empty()
    {
        return (*_source).empty;
    }

    @property bool front()
    {
        return readBits!int(1) != 0;
    }

    void popFront()
    {
        _consumedBits++;
        if (_consumedBits == 8)
        {
            _consumedBits = 0;
            (*_source).popFront();
        }
    }

    T readBits(T)(uint bits) if (isIntegral!T)
    in {
        assert(bits <= 8*T.sizeof);
    }
    body {

        import std.algorithm : min;

        // 2 consumed, 3 bits
        //
        // 1.
        // source   abcdefgh
        //            ^  |
        //  rshift   srcMask     resMask
        //       3  00111000    00000111
        // num  00000cde
        // res  00000cde

        // 3 consumed, 6 bits
        //
        // 1.
        // source   abcdefgh abcdefgh
        //             ^      |
        //  lshift   srcMask     resMask
        //       1  00011111    00111110
        // num  00defgh0
        // res  00defgh0
        // popFront
        //
        // 2.
        // source   abcdefgh
        //          ^|
        //  rshift   srcMask     resMask
        //       1  10000000    00000001
        // num  0000000a
        // res  00defgha

        // 3 consumed, 9 bits
        //
        // 1.
        // source   abcdefgh abcdefgh
        //             ^         |
        //  lshift   srcMask     resMask
        //       4  00011111    00000001 11110000
        // num  0000000d efgh0000
        // res  0000000d efgh0000
        // popFront
        //
        // 2.
        // source   abcdefgh
        //          ^   |
        //  rshift   srcMask     resMask
        //       1  11110000    00001111
        // num  00000000 0000abcd
        // res  0000000d efghabcd

        T res = 0;
        do
        {
            enforce(!(*_source).empty);

            if (bits < 8-_consumedBits)
            {
                // right shifting
                immutable resMask = 0xff >>> (8-bits);
                immutable shift = (8 - (bits+_consumedBits));
                assert((resMask << shift) <= 255);
                immutable srcMask = cast(ubyte)(resMask << shift);

                res |= ((*_source).front & srcMask) >>> shift;

                _consumedBits += bits;
                bits = 0;
            }
            else
            {
                // left shifting
                immutable shift = (bits+_consumedBits - 8); // possibly 0
                immutable srcMask = cast(ubyte)(0xff >>> _consumedBits);

                res |= ((*_source).front & srcMask) << shift;

                bits -= (8-_consumedBits);
                _consumedBits = 8;
            }

            if (_consumedBits == 8)
            {
                _consumedBits = 0;
                (*_source).popFront();
            }

        }
        while(bits != 0);

        return res;
    }

private:

    R *_source;
    ubyte _consumedBits;
}

unittest
{
    auto data = [   ubyte(0b0101_0101),
                    ubyte(0b1010_1010),
                    ubyte(0b0011_0011),
                    ubyte(0b1100_1100)  ];
    auto br = bitRange(data);
    assert(br.readBits!uint(3) == 0b010);
    assert(br.readBits!ubyte(6) == 0b1_0101_1);
    assert(br.readBits!ushort(7) == 0b010_1010);
    assert(data.length == 2);
    assert(br.readBits!ushort(16) == 0b0011_0011_1100_1100);
    assert(data.length == 0);
}
