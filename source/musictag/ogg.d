module musictag.ogg;

import musictag.taggedfile;
import musictag.tag;
import musictag.utils;

import std.exception : enforce;


class OggFile : TaggedFile
{
    @property Format format() const { return Format.Ogg; }

    @property inout(Tag) tag() inout { return null; }
}

class OggPageHeader
{
    this (const(ubyte)[] data)
    {
        enforce(data.length >= 27);
        assert(data[0 .. 4] == ['O', 'g', 'g', 'S']);
        _streamVersion = data[4];
        _flags = data[5];
        _position = decodeLittleEndian!ulong(data[6 .. 14]);
        _streamSerialNumber = decodeLittleEndian!uint(data[14 .. 18]);
        _pageSequence = decodeLittleEndian!uint(data[18 .. 22]);
        _pageChecksum = decodeLittleEndian!uint(data[22 .. 26]);
        _numSegments =  data[26];
        enforce(data.length >= 27 + _numSegments);
        _segmentSizes = data[27 .. 27+numSegments].idup;
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

class OggPage
{

}