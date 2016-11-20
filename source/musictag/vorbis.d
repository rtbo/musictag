module musictag.vorbis;

import musictag.xiph : XiphTag, XiphComment;
import musictag.support : decodeLittleEndian;
import musictag.bitstream : isBytesInputRange;

import std.exception : enforce;


XiphTag readVorbisTag(string filename)
{
    import musictag.bitstream : BufferedFileRange;
    import std.stdio : File;

    return readVorbisTag(BufferedFileRange(File(filename, "rb")));
}

XiphTag readVorbisTag(R)(R br) if (isBytesInputRange!R)
{
    import musictag.ogg : oggPageRange, oggPacketRange;
    import std.algorithm : map;

    auto pages = oggPageRange(br);
    auto packets = oggPacketRange(pages);
    foreach (p; packets.map!(p => Packet(p)))
    {
        if (p.type == Packet.Type.Comment)
        {
            immutable headerMarker = cast(immutable(ubyte[]))"vorbis";
            enforce(p.data[1 .. 7] == headerMarker);
            return new XiphTag(XiphComment(p.data[7 .. $]), br.name);
        }
    }
    return null;
}


struct Packet
{
    enum Type
    {
        Identification,
        Comment,
        Setup,
        Audio,
    }

    @property Type type() const
    {
        immutable b1 = _data[0];
        switch(b1)
        {
            case 1: return Type.Identification;
            case 3: return Type.Comment;
            case 5: return Type.Setup;
            default: break;
        }
        if ((b1 & 0x01) == 0) return Type.Audio;
        else throw new Exception("invalid vorbis packet leading byte");
    }

    @property const(ubyte)[] data() const
    {
        return _data;
    }

private:

    ubyte[] _data;
}
