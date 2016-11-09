module musictag.id3v2.builtinframes;

import musictag.id3v2.frame;
import musictag.id3v2.support;


class UFIDFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "UFID");
        super(header);
        parse(data);
    }

    @property string owner() const { return _owner; }
    @property inout(ubyte)[] data() inout { return _data; }

private:

    void parse(const(ubyte)[] data)
    {
        _owner = decodeLatin1(data);
        _data = data.dup;
    }

    string _owner;
    ubyte[] _data;
}


class TextInformationFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id.length && header.id[0] == 'T' && header.id != "TXXX");
        super(header);
        parse(data);
    }

    @property string text() const { return _text; }

private:

    void parse(const(ubyte)[] data)
    {
        import std.exception : enforce;
        enforce(data.length > 0);
        auto encodingByte = data[0];
        data = data[1 .. $];
        _text = decodeString(data, encodingByte);
        enforce(data.length == 0);
    }

    string _text;
}
