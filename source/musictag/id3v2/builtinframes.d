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
        _data = data;
    }

    string _owner;
    ubyte[] _data;
}
