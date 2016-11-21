module musictag.xiph;

import musictag.tag : Tag;
import musictag.bitstream;

/// Xiph comment tag
class XiphTag : Tag
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
    @property const(ubyte)[] picture() const
    {
        return null;
    }

    /// direct access to the XiphComment
    @property const(XiphComment) comment() const { return _comment; }

private:

    XiphComment _comment;
    string _filename;
}


struct XiphComment
{
    @property string vendor() const { return _vendor; }

    const(string)* test(string id) const { return id in _comments; }

    string opIndex(string id) const { return _comments[id]; }

    this(const(ubyte)[] data)
    {
        import std.algorithm : findSplit;
        import std.exception : enforce;

        auto orig = data.length;
        immutable vlen = data.readLittleEndian!uint(4);
        assert(orig == data.length+4);
        enforce(data.length >= vlen+4, "corrupted XiphComment");
        _vendor = data.readStringUtf8(vlen);

        uint num = data.readLittleEndian!uint(4);
        while(num-- && data.length > 4)
        {
            import std.uni : toUpper;

            immutable len = data.readLittleEndian!uint(4);
            enforce(data.length >= len, "corrupted XiphComment");

            string field = data.readStringUtf8(len);

            immutable split = findSplit(field, "=");
            enforce(split[0].length && split[2].length);
            _comments[toUpper(split[0])] = split[2];
        }
    }


private:

    string _vendor;
    string[string] _comments;
}
