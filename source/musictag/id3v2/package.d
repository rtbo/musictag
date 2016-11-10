module musictag.id3v2;

import musictag.id3v2.header;
import musictag.id3v2.extendedheader;
import musictag.id3v2.footer;
import musictag.id3v2.framefactory;
import musictag.id3v2.frame;
import musictag.tag;
import std.stdio;
import std.exception : enforce;


class Id3v2Tag : Tag
{
    this(File f, size_t offset, FrameFactoryDg factoryDg)
    {
        _offset = offset;
        read(f, factoryDg);
    }

    @property string filename() const { return _filename; }
    @property Format format() const { return Format.Id3v2; }

    @property string frame(string identifier) const { return ""; }

    @property string artist() const { return ""; }
    @property string title() const { return ""; }
    @property int track() const { return 0; }
    @property string composer() const { return ""; }
    @property string year() const { return ""; }
    @property const(byte)[] picture() const { return []; }

    @property size_t offset() const { return _offset; }
    @property size_t size() const { return _header.tagSize; }

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
