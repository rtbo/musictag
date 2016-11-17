module musictag.ogg;

import musictag.taggedfile;
import musictag.tag;
import musictag.support;

import std.exception : enforce, assumeUnique;
import std.range : isInputRange, ElementType;


enum isOggPageInputRange(R) = isInputRange!R && is(ElementType!R == OggPage);


immutable(ubyte)[] capturePattern = ['O', 'g', 'g', 'S'];


/// Input range of Ogg page
/// The front property always return page with the same data buffer
/// (filled with new data after each popFront call), therefore
/// the dup property of the page data should be used if a reference
/// to it is to be kept
struct OggPageRange(R) if (isBytesInputRange!R)
{
    this (R range)
    {
        _range = range;
        _page = new OggPage;
        next();
    }

    @property bool empty()
    {
        return _range.empty;
    }

    @property auto front()
    {
        return OggPage(_header, _data);
    }

    void popFront()
    {
        next();
    }

private:

    void next()
    {
        _range.findPattern(capturePattern);
        if (!_range.empty)
        {
            auto headerBytes = readBytes(_range, new ubyte[OggPageHeader.commonSize]);
            _header = OggPageHeader(headerBytes, _range);
            _data.length = _header.pageSize;
            _data = readBytes(_range, _data);
        }
    }

    R _range;
    OggPageHeader _header;
    ubyte[] _data;
}


struct OggPage
{

    @property const(OggPageHeader) header() const { return _header; }
    @property const(ubyte)[] data() const { return _data; }

private:

    this(OggPageHeader header, const(ubyte)[] data)
    {
        _header = header;
        _data = data;
    }

    OggPageHeader _header;
    const(ubyte)[] _data;
}


struct OggPageHeader
{

    @property ubyte streamVersion() const { return _streamVersion; }
    @property bool continuedPacket() const { return (_flags & 0x01) == 0x01; }
    @property bool firstPage() const { return (_flags & 0x02) == 0x02; }
    @property bool lastPage() const { return (_flags & 0x04) == 0x04; }
    @property ulong position() const { return _position; }
    @property uint streamSerialNumber() const { return _streamSerialNumber; }
    @property uint pageSequence() const { return _pageSequence; }
    @property uint pageChecksum() const { return _pageChecksum; }
    @property size_t numSegments() const { return _numSegments; }
    @property const(ubyte)[] segmentSizes() const { return _segmentSizes; }

    @property size_t headerSize() const {
        return commonSize + _numSegments;
    }

    @property size_t pageSize() const {
        import std.algorithm : sum;
        return _segmentSizes.sum();
    }

private:

    enum commonSize = 27;
    
    this (R)(const(ubyte)[] data, R r)
    {
        assert(data.length == commonSize && data[0 .. 4] == capturePattern);
        _streamVersion = data[4];
        _flags = data[5];
        _position = decodeLittleEndian!ulong(data[6 .. 14]);
        _streamSerialNumber = decodeLittleEndian!uint(data[14 .. 18]);
        _pageSequence = decodeLittleEndian!uint(data[18 .. 22]);
        _pageChecksum = decodeLittleEndian!uint(data[22 .. 26]);
        _numSegments =  data[26];

        _segmentSizes = readBytes(r, new ubyte[_numSegments]);
        enforce(_segmentSizes.length == _numSegments);
    }

    ubyte   _streamVersion;
    ubyte   _flags;
    ulong   _position;
    uint    _streamSerialNumber;
    uint    _pageSequence;
    uint    _pageChecksum;
    ubyte   _numSegments;
    ubyte[] _segmentSizes;
}