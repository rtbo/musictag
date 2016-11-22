module musictag.id3v2;

import musictag.id3v2.extendedheader;
import musictag.id3v2.footer;
import musictag.id3v2.framefactory;
import musictag.id3v2.frame;
import musictag.tag;
import musictag.bitstream;

import std.exception : enforce;
import std.bitmanip : bitfields;


immutable(ubyte[]) streamPattern = ['I', 'D', '3'];

Id3v2Tag readId3v2Tag(string filename, FrameFactoryDg factoryDg=null)
{
    import std.stdio : File;
    return readId3v2Tag(byteRange(File(filename, "rb")), factoryDg);
}

Id3v2Tag readId3v2Tag(R)(R range, FrameFactoryDg factoryDg=null)
{
    range.eatPattern(streamPattern);
    enforce(!range.empty);

    ubyte[Id3v2Header.size] headerData;
    auto header = Id3v2Header.parse(range.readBytes(headerData[]));

    auto tagData = range.readBytes(new ubyte[header.tagSize]);
    enforce(tagData.length == header.tagSize);

    if (header.unsynchronize)
    {
        import musictag.id3v2.support : decodeUnsynchronizedTag;
        tagData = decodeUnsynchronizedTag(tagData);
    }

    auto frameData = tagData;
    ExtendedHeader extendedHeader;
    Frame[string] frames;

    if (header.extendedHeader)
    {
        extendedHeader = new ExtendedHeader(tagData, header.majVersion);
        frameData = frameData[extendedHeader.size .. $];
    }

    if (header.footer)
    {
        frameData = frameData[0 .. $-Footer.size];
    }

    auto frameFactory = factoryDg ? factoryDg(header) :
                                    defaultFrameFactory(header);

    while(frameData.length > FrameHeader.size)
    {
        // have we hit the padding?
        if (frameData[0] == 0) break;

        auto frameHeader = FrameHeader.parse(frameData, header.majVersion);
        immutable frameEnd = FrameHeader.size + frameHeader.frameSize;
        enforce(frameData.length >= frameEnd);

        auto frame = frameFactory.createFrame(frameHeader, frameData[FrameHeader.size .. frameEnd]);
        if (frame) frames[frame.identifier] = frame;

        frameData = frameData[frameEnd .. $];
    }

    string filename;
    static if (hasName!R)
    {
        filename = range.name;
    }
    return new Id3v2Tag(filename, header, extendedHeader, frames);
}


/// An ID3V2 tag
class Id3v2Tag : Tag
{

    /// Implementation of Tag interface
    @property string filename() const { return _filename; }

    /// ditto
    @property Format format() const { return Format.Id3v2; }

    /// ditto
    @property string artist() const
    {
        return textFrame("TPE1");
    }

    /// ditto
    @property string title() const
    {
        return textFrame("TIT2");
    }

    /// ditto
    @property int track() const
    {
        immutable trck = textFrame("TRCK");
        if (trck.length)
        {
            import std.array : split;
            import std.conv : to;
            return trck.split("/")[0].to!int;
        }
        return -1;
    }

    /// ditto
    @property int pos() const
    {
        immutable tpos = textFrame("TPOS");
        if (tpos.length)
        {
            import std.array : split;
            import std.conv : to;
            return tpos.split("/")[0].to!int;
        }
        return -1;
    }

    /// ditto
    @property string composer() const
    {
        return textFrame("TCOM");
    }

    /// ditto
    @property int year() const
    {
        immutable tdrl = textFrame("TDRL");
        if (tdrl.length >= 4)
        {
            import std.conv : to;
            return tdrl[0 .. 4].to!int;
        }
        return -1;
    }

    /// ditto
    @property const(ubyte)[] picture() const { return []; }

    /// Get the value of a text frame
    @property string textFrame(string identifier) const {
        auto frame = identifier in _frames;
        if (frame) {
            import musictag.id3v2.builtinframes : TextFrame;
            auto textFrame = cast(const(TextFrame))(*frame);
            if (textFrame) return textFrame.text;
        }
        return "";
    }
private:

    this(string filename, Id3v2Header header, ExtendedHeader extendedHeader, Frame[string] frames)
    {
        _filename = filename;
        _header = header;
        _extendedHeader = extendedHeader;
        _frames = frames;
    }

    string _filename;
    Id3v2Header _header;
    ExtendedHeader _extendedHeader;
    Frame[string] _frames;
}


/// Id3v2 Header (§3.1).
struct Id3v2Header
{
    /// Fields as described in the header definition §3.1
    @property uint majVersion() const { return _majVersion; }
    /// ditto
    @property uint revision() const { return _revision; }
    /// ditto
    @property bool unsynchronize() const { return _flags.unsynchronize; }
    /// ditto
    @property bool extendedHeader() const { return _flags.extendedHeader; }
    /// ditto
    @property bool experimental() const { return _flags.experimental; }
    /// ditto
    @property bool footer() const { return _flags.footer; }
    /// ditto
    @property size_t tagSize() const { return _tagSize; }

    /// The size of the Id3v2 header (always 7)
    enum size_t size = 7;

    /// Parses bytes data into a header.
    /// Assumes that data starts at first byte after "ID3".
    /// The data must start with identifier and have length >= size
    static Id3v2Header parse(const(ubyte)[] data)
    in
    {
        assert(data.length >= size);
    }
    body
    {
        return Id3v2Header (
            data[0], data[1], cast(Flags)data[2],
            ((data[3] & 0x7f) << 21) | ((data[4] & 0x7f) << 14) |
            ((data[5] & 0x7f) << 7)  | (data[6] & 0x7f)
        );
    }

private:

    struct Flags
    {
        mixin(bitfields!(
            uint, "", 4,
            bool, "footer", 1,
            bool, "experimental", 1,
            bool, "extendedHeader", 1,
            bool, "unsynchronize", 1,
        ));
    }
    static assert(Flags.sizeof == 1);
    unittest {
        Flags f = cast(Flags)0b01110000;
        assert(!f.unsynchronize);
        assert( f.extendedHeader);
        assert( f.experimental);
        assert( f.footer);
    }

    ubyte _majVersion;
    ubyte _revision;
    Flags _flags;
    uint _tagSize;

}
