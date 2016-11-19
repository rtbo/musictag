module musictag.vorbis;

import musictag.tag;
import musictag.ogg;
import musictag.support : isBytesInputRange, decodeLittleEndian;

import std.exception : enforce;


/// Xiph comment tag
class VorbisTag : Tag
{
    this(XiphComment comment, string filename)
    {
        _comment = comment;
        _filename = filename;
    }

    /// Implementation of Tag
    @property string filename() const
    {
        return _filename;
    }

    /// Ditto
    @property Format format() const
    {
        return Format.Vorbis;
    }

    /// Ditto
    @property string artist() const
    {
        return comment["ARTIST"];
    }

    /// Ditto
    @property string title() const
    {
        return comment["TITLE"];
    }

    /// Ditto
    @property int track() const
    {
        auto trck = comment.test("TRACK");
        if (trck)
        {
            try
            {
                import std.conv : to;
                return (*trck).to!int;
            }
            catch(Exception ex) {}
        }
        return -1;
    }

    /// Ditto
    @property int pos() const
    {
        return -1;
    }

    /// Ditto
    @property string composer() const
    {
        /// FIXME: check how to make ARTIST/PERFORMER
        /// consistent with other tag types
        return "";
    }

    /// Ditto
    @property int year() const
    {
        auto date = comment.test("DATE");
        if (date)
        {
            try
            {
                import std.conv : to;
                return (*date).to!int;
            }
            catch(Exception ex) {}
        }
        return -1;
    }

    /// Ditto
    @property const(byte)[] picture() const
    {
        return null;
    }

    /// direct access to the XiphComment
    @property const(XiphComment) comment() const { return _comment; }

private:

    XiphComment _comment;
    string _filename;
}


VorbisTag readVorbisTag(string filename)
{
    import musictag.support : BufferedFileRange;
    import std.stdio : File;

    return readVorbisTag(BufferedFileRange(File(filename, "rb")));
}

VorbisTag readVorbisTag(R)(R br) if (isBytesInputRange!R)
{
    import musictag.ogg : oggPageRange, oggPacketRange;
    import std.algorithm : map;

    auto pages = oggPageRange(br);
    auto packets = oggPacketRange(pages);
    foreach (p; packets.map!(p => Packet(p)))
    {
        if (p.type == Packet.Type.Comment)
        {
            return new VorbisTag(XiphComment(p.data), br.name);
        }
    }
    return null;
}


struct XiphComment
{
    @property string vendor() const { return _vendor; }

    const(string)* test(string id) const { return id in _comments; }

    string opIndex(string id) const { return _comments[id]; }

private:

    this(const(ubyte)[] data)
    {
        import std.algorithm : findSplit;

        assert(data[0] == 3);
        enforce(cast(string)data[1 .. 7] == "vorbis");
        data = data[7 .. $];

        immutable vlen = decodeLittleEndian!uint(data[0 .. 4]);
        enforce(data.length > vlen+4, "corrupted XiphComment");

        _vendor = cast(string)data[4 .. vlen+4].idup;
        uint num = decodeLittleEndian!uint(data[4+vlen .. 8+vlen]);
        data = data[8+vlen .. $];

        while(num-- && data.length > 4)
        {
            import std.uni : toUpper;

            immutable len = decodeLittleEndian!uint(data[0 .. 4]);
            enforce(data.length > 4+len, "corrupted XiphComment");

            string field = cast(string)data[4 .. 4+len];
            immutable split = findSplit(field, "=");
            enforce(split[0].length && split[2].length);
            _comments[toUpper(split[0])] = split[2];

            data = data[4+len .. $];
        }
    }

    string _vendor;
    string[string] _comments;
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
