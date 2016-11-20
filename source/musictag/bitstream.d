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


private alias FileByChunk = typeof(File("f", "rb").byChunk(4));


/// Checks weither T conforms to ByteChunkRange static interface,
/// which is an input range of byte chunks (aka ubyte[])
enum isByteChunkRange(T) =  isInputRange!T &&
                            is(Unqual!(ElementType!T) == ubyte[]);

static assert(isByteChunkRange!FileByChunk);

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


// TODO:    check design of reader function that returns the range
//          to give chaining possibility

/// Read bytes from the supplied BytesInputRange to the supplied buffer
/// and return what could be read.
/// Takes advantage of readBuf method if available.
// ubyte[] readBytes(R)(ref R range, ubyte[] buf)
// if (isByteRange!R && hasReadBuf!R)
// {
//     return range.readBuf(buf);
// }

/// Ditto
// ubyte[] readBytes(R)(ref R range, ubyte[] buf)
// if (isBytesRange!R && !hasReadBuf!R)
// {
//     size_t pos;
//     while(pos < buf.length && !range.empty)
//     {
//         buf[pos] = range.front;
//         pos++;
//         range.popFront();
//     }
//     return buf[0 .. pos];
// }


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
            res |= range.front << shift;
            range.popFront();
        }
        return res;
    }
}


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



auto bitRange(R)(ref R source)
if (isInputRange!R && is(Unqual!(ElementType!R) == ubyte))
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
