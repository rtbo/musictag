module musictag.ogg;

import musictag.taggedfile;
import musictag.tag;
import musictag.support;

import std.exception : enforce, assumeUnique;
import std.stdio : File;


immutable(ubyte)[] capturePattern = ['O', 'g', 'g', 'S'];

struct OggPageRange
{

}

class OggPage
{
    this(OggPageHeader header, File f)
    {
        _header = header;
        _pageData = assumeUnique(f.rawRead(new ubyte[_header.pageSize]));
    }

    @property const(OggPageHeader) header() const { return _header; }
    @property immutable(ubyte)[] pageData() const { return _pageData; }

private:

    OggPageHeader _header;
    immutable(ubyte)[] _pageData;
}


class OggPageHeader
{
    this (const(ubyte)[] data, File f)
    {
        assert(data.length == 27 && data[0 .. 4] == capturePattern);
        _streamVersion = data[4];
        _flags = data[5];
        _position = decodeLittleEndian!ulong(data[6 .. 14]);
        _streamSerialNumber = decodeLittleEndian!uint(data[14 .. 18]);
        _pageSequence = decodeLittleEndian!uint(data[18 .. 22]);
        _pageChecksum = decodeLittleEndian!uint(data[22 .. 26]);
        _numSegments =  data[26];

        _segmentSizes = assumeUnique(f.rawRead(new ubyte[_numSegments]));
        enforce(_segmentSizes.length == _numSegments);
    }

    @property ubyte streamVersion() const { return _streamVersion; }
    @property bool continuedPacket() const { return (_flags & 0x01) == 0x01; }
    @property bool firstPage() const { return (_flags & 0x02) == 0x02; }
    @property bool lastPage() const { return (_flags & 0x04) == 0x04; }
    @property ulong position() const { return _position; }
    @property uint streamSerialNumber() const { return _streamSerialNumber; }
    @property uint pageSequence() const { return _pageSequence; }
    @property uint pageChecksum() const { return _pageChecksum; }
    @property size_t numSegments() const { return _numSegments; }
    @property immutable(ubyte)[] segmentSizes() const { return _segmentSizes; }

    @property size_t headerSize() const {
        return 27 + _numSegments;
    }

    @property size_t pageSize() const {
        import std.algorithm : sum;
        return _segmentSizes.sum();
    }

private:

    ubyte               _streamVersion;
    ubyte               _flags;
    ulong               _position;
    uint                _streamSerialNumber;
    uint                _pageSequence;
    uint                _pageChecksum;
    ubyte               _numSegments;
    immutable(ubyte)[]  _segmentSizes;
}