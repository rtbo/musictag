module musictag.id3v2;

import musictag.id3v2.extendedheader;
import musictag.id3v2.footer;
import musictag.id3v2.framefactory;
import musictag.id3v2.frame;
import musictag.tag;

import std.stdio;
import std.exception : enforce;
import std.bitmanip : bitfields;


/// An ID3V2 tag
class Id3v2Tag : Tag
{

    /// Builds an Id3v2 tag with an opened file, offset and frame factory.
    /// The Tag must start at offset
    this(File f, size_t offset, FrameFactoryDg factoryDg)
    {
        _offset = offset;
        read(f, factoryDg);
    }

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

    /// Offset the tag is located (most often 0 with id3v2)
    @property size_t offset() const { return _offset; }

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

    void read(File file, FrameFactoryDg factoryDg)
    {
        import std.algorithm : startsWith;

        ubyte[Id3v2Header.size] headerData;
        file.seek(_offset);
        enforce(file.rawRead(headerData[]).length == Id3v2Header.size);

        assert(headerData[].startsWith(Id3v2Header.identifier[]));

        _header = Id3v2Header.parse(headerData[]);

        auto tagData = file.rawRead(new ubyte[_header.tagSize]);
        enforce(tagData.length == _header.tagSize);

        if (_header.unsynchronize)
        {
            import musictag.id3v2.support : decodeUnsynchronizedTag;
            tagData = decodeUnsynchronizedTag(tagData);
        }

        auto frameData = tagData;

        if (_header.extendedHeader)
        {
            _extendedHeader = new ExtendedHeader(tagData, _header.majVersion);
            frameData = frameData[_extendedHeader.size .. $];
        }

        if (_header.footer)
        {
            frameData = frameData[0 .. $-Footer.size];
        }

        if (factoryDg) _frameFactory = factoryDg(_header);
        else _frameFactory = defaultFrameFactory(_header);

        while(frameData.length > FrameHeader.size)
        {
            // have we hit the padding?
            if (frameData[0] == 0) break;

            auto frameHeader = FrameHeader.parse(frameData, _header.majVersion);
            immutable frameEnd = FrameHeader.size + frameHeader.frameSize;
            enforce(frameData.length >= frameEnd);

            auto frame = _frameFactory.createFrame(frameHeader, frameData[FrameHeader.size .. frameEnd]);
            if (frame) _frames[frame.identifier] = frame;

            frameData = frameData[frameEnd .. $];
        }

    }

    string _filename;
    size_t _offset;
    Id3v2Header _header;
    ExtendedHeader _extendedHeader;
    FrameFactory _frameFactory;
    Frame[string] _frames;
}


/// Id3v2 Header (§3.1)
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

    /// The size of the Id3v2 header (always 10)
    enum size_t size = 10;
    /// The identifier marking the start of the header preceding a Tag
    static @property ubyte[3] identifier() { return ['I', 'D', '3']; }

    /// Parses bytes data into a header.
    /// The data must start with identifier and have length >= size
    static Id3v2Header parse(const(ubyte)[] data)
    in {
        assert(data.length >= size);
        assert(data[0 .. 3] == identifier);
    }
    body {
        return Id3v2Header (
            data[3], data[4], cast(Flags)data[5],
            ((data[6] & 0x7f) << 21) | ((data[7] & 0x7f) << 14) |
            ((data[8] & 0x7f) << 7)  | (data[9] & 0x7f)
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
