module musictag.flac;

import musictag.xiph : XiphTag, XiphComment;
import musictag.support : decodeBigEndian;
import musictag.bitstream;

import std.exception : enforce;

immutable(ubyte[]) streamPattern = ['f', 'L', 'a', 'C'];

class FlacTag : XiphTag
{
    /// Overrides XiphTag.picture in order to provide the picture content
    /// from a flac PICTURE metadata block
    override @property const(ubyte)[] picture() const
    {
        return _picture.data;
    }

private:
    this(XiphComment comment, string filename, PictureBlock picture)
    {
        super(comment, filename);
        _picture = picture;
    }

    PictureBlock _picture;
}

FlacTag readFlacTag(string filename)
{
    import musictag.bitstream : BufferedFileRange;
    import std.stdio : File;
    return readFlacTag(BufferedFileRange(File(filename, "rb")));
}

FlacTag readFlacTag(R)(R source)
if (isBytesInputRange!R)
{
    import std.stdio;
    ubyte[4] buf4;
    ubyte[] buf;
    // must be at the start of stream
    enforce(source.findPattern(streamPattern) == 0);
    readBytes(source, buf4[]); // eat pattern. FIXME: change that sh..

    XiphComment comment;
    PictureBlock picture;
    bool foundComment;
    bool foundPicture;

    while (!source.empty)
    {
        immutable header = MetadataBlockHeader(readBytes(source, buf4[]));
        writefln("header.type = %s", header.type);
        writefln("header.isLast = %s", header.isLast);
        writefln("header.size = %s", header.size);

        buf.length = header.size;
        auto data = readBytes(source, buf);

        if (header.type == BlockType.VorbisComment)
        {
            comment = XiphComment(data);
            foundComment = true;
        }
        else if (header.type == BlockType.Picture)
        {
            foundPicture = true;
            picture = PictureBlock(data);
            writeln("picture size: ", picture.data.length);
        }

        if (foundComment && foundPicture) break;
        if (header.isLast) break;
    }
    if (foundComment) return new FlacTag(comment, source.name, picture);
    else return null;
}

enum BlockType
{
    StreamInfo      = 0,
    Padding         = 1,
    Application     = 2,
    SeekTable       = 3,
    VorbisComment   = 4,
    CueSheet        = 5,
    Picture         = 6,
    ReservedFirst   = 7,
    ReservedLast    = 126,
    Invalid         = 127,
}

struct MetadataBlockHeader
{
    @property bool isLast() const
    {
        return (_data & 0x80000000) != 0;
    }

    @property BlockType type() const
    {
        return cast(BlockType)((_data & 0x7f000000) >>> 24);
    }

    @property size_t size() const
    {
        return _data & 0x00ffffff;
    }

private:

    this (const(ubyte)[] data)
    {
        _data = decodeBigEndian!uint(data[0 .. 4]);
    }

    uint _data;
}


struct StreamInfoBlock
{
    @property size_t minBlockSize() const { return _minBlockSize; }
    @property size_t maxBlockSize() const { return _maxBlockSize; }
    @property size_t minFrameSize() const { return _minFrameSize; }
    @property size_t maxFrameSize() const { return _maxFrameSize; }
    @property uint sampleRate() const { return _sampleRate; }
    @property size_t channelCount() const { return _channelCount; }
    @property size_t bitsPerSample() const { return _bitsPerSample; }
    @property ulong sampleCount() const { return _sampleCount; }
    @property ubyte[16] md5sum() const { return _md5sum; }

private:

    this(const(ubyte)[] data)
    {
        enforce(data.length >= 34);

        auto br = bitRange(data);

        _minBlockSize = br.readBits!ushort(16);
        _maxBlockSize = br.readBits!ushort(16);
        _minFrameSize = br.readBits!uint(24);
        _maxFrameSize = br.readBits!uint(24);
        _sampleRate = br.readBits!uint(20);
        _channelCount = cast(ubyte)(br.readBits!ubyte(3) + 1);
        _bitsPerSample = cast(ubyte)(br.readBits!ubyte(5) + 1);
        _sampleCount = br.readBits!ulong(36);
        _md5sum = data[0 .. 16];
    }

    ushort _minBlockSize;
    ushort _maxBlockSize;
    uint _minFrameSize;
    uint _maxFrameSize;
    uint _sampleRate;
    ubyte _channelCount;
    ubyte _bitsPerSample;
    ulong _sampleCount;
    ubyte[16] _md5sum;
}


enum PictureType
{
    Other               = 0x00,
    fileIcon32x32       = 0x01,
    fileIconOther       = 0x02,
    CoverFront          = 0x03,
    CoverBack           = 0x04,
    LeafletPage         = 0x05,
    Media               = 0x06,
    LeadArtist          = 0x07,
    Artist              = 0x08,
    Conductor           = 0x09,
    Band                = 0x0A,
    Composer            = 0x0B,
    Lyricist            = 0x0C,
    RecordingLocation   = 0x0D,
    DuringRecording     = 0x0E,
    DuringPerformance   = 0x0F,
    MovieCapture        = 0x10,
    BrightColouredFish  = 0x11,  // ??
    Illustration        = 0x12,
    BandLogotype        = 0x13,
    PublisherLogotype   = 0x14,
}


struct PictureBlock
{

    @property PictureType pictureType() const { return _pictureType; }
    @property string mimeType() const { return _mimeType; }
    @property string description() const { return _description; }
    @property uint width() const { return _width; }
    @property uint height() const { return _height; }
    @property uint colorDepth() const { return _colorDepth; }
    @property uint numColors() const { return _numColors; }
    @property const(ubyte)[] data() const { return _data; }

private:

    this(const(ubyte)[] data)
    {
        _pictureType = cast(PictureType)(decodeBigEndian!uint(data[0 .. 4]));
        auto l = decodeBigEndian!uint(data[4 .. 8]);
        _mimeType = cast(string)(data[8 .. 8+l]);
        data = data[8+l .. $];
        l = decodeBigEndian!uint(data[0 .. 4]);
        _description = cast(string)(data[4 .. 4+l]);
        data = data[4+l .. $];
        _width = decodeBigEndian!uint(data[0 .. 4]);
        _height = decodeBigEndian!uint(data[4 .. 8]);
        _colorDepth = decodeBigEndian!uint(data[8 .. 12]);
        _numColors = decodeBigEndian!uint(data[12 .. 16]);
        l = decodeBigEndian!uint(data[16 .. 20]);
        _data = data[20 .. $].dup;
    }

    PictureType _pictureType;
    string _mimeType;
    string _description;
    uint _width;
    uint _height;
    uint _colorDepth;
    uint _numColors;
    ubyte[] _data;
}
