module musictag.id3v2;

import musictag.id3v2.header;
import musictag.id3v2.extendedheader;
import musictag.id3v2.footer;
import musictag.id3v2.framefactory;
import musictag.id3v2.frame;
import musictag.tag;
import std.stdio;
import std.exception : enforce;


/// An ID3V2 tag
class Id3v2Tag : Tag
{
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
    @property const(byte)[] picture() const { return []; }

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

        ubyte[Header.size] headerData;
        file.seek(_offset);
        enforce(file.rawRead(headerData[]).length == Header.size);

        assert(headerData[].startsWith(Header.identifier[]));

        _header = Header.parse(headerData[]);

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
    Header _header;
    ExtendedHeader _extendedHeader;
    FrameFactory _frameFactory;
    Frame[string] _frames;
}
