module musictag.ogg;

import musictag.tag : Tag;
import musictag.bitstream;

import std.exception : enforce, assumeUnique;
import std.range : isInputRange, ElementType;


enum isOggPageRange(R) = isInputRange!R && is(ElementType!R == OggPage);


immutable(ubyte)[] capturePattern = ['O', 'g', 'g', 'S'];


/// Builds input range of Ogg page
/// The front property always return page with the same data buffer
/// (filled with new data after each popFront call), therefore
/// the dup property of the page data should be used if a reference
/// to it is to be kept
auto oggPageRange(R)(R range) if (isByteRange!R)
{
    return OggPageRange!R(range);
}


private struct OggPageRange(R) if (isByteRange!R)
{
    this (R range)
    {
        _range = range;
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
        _range.eatPattern(capturePattern);
        if (!_range.empty)
        {
            _header = OggPageHeader.parse(_range);
            _data.length = _header.pageSize;
            _data = readBytes(_range, _data);
        }
    }

    R _range;
    OggPageHeader _header;
    ubyte[] _data;
}

static assert(isOggPageRange!(OggPageRange!FileByteRange));


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

    enum commonSize = 23;

    static OggPageHeader parse(R)(ref R r)
    {
        OggPageHeader oph;
        oph._streamVersion = r.readByte();
        oph._flags = r.readByte();
        oph._position = r.readLittleEndian!ulong(8);
        oph._streamSerialNumber = r.readLittleEndian!uint(4);
        oph._pageSequence = r.readLittleEndian!uint(4);
        oph._pageChecksum = r.readLittleEndian!uint(4);
        oph._numSegments =  r.readByte();

        oph._segmentSizes = r.readBytes(new ubyte[oph._numSegments]);
        enforce(oph._segmentSizes.length == oph._numSegments);

        return oph;
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



auto oggPacketRange(R)(R source) if (isOggPageRange!R)
{
    struct Result
    {
        this(R source)
        {
            _source = source;
            next();
        }

        @property bool empty()
        {
            return !_packet.length && _source.empty;
        }

        @property ubyte[] front()
        {
            return _packet;
        }

        void popFront()
        {
            next();
        }

    private:
        void next()
        {
            _packet = [];
            if(_source.empty) return;

            OggPage p = _source.front;
            size_t start = _segOffset;
            size_t end = _segOffset;
            ubyte segSize = void;

            do
            {
                segSize = p.header.segmentSizes[_nextSeg++];
                end += segSize;

                if (segSize != 0xff)
                {
                    _packet ~= p.data[start .. end].dup;
                    if (_nextSeg == p.header.segmentSizes.length)
                    {
                        _source.popFront();
                        _nextSeg = 0;
                        start = 0;
                        end = 0;
                    }
                }
                else if (_nextSeg == p.header.segmentSizes.length)
                {
                    assert(end == p.data.length);
                    _packet ~= p.data[start .. $];
                    _source.popFront();
                    p = _source.front;
                    _nextSeg = 0;
                    start = 0;
                    end = 0;
                }
            }
            while(segSize == 0xff);

            _segOffset = end;
        }

        R _source;
        size_t _segOffset;
        size_t _nextSeg;
        ubyte[] _packet;
    }

    return Result(source);
}
