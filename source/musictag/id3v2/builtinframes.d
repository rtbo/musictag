module musictag.id3v2.builtinframes;

import musictag.id3v2.frame;
import musictag.id3v2.support;

import std.exception : enforce;


class UFIDFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "UFID");
        super(header);
        _owner = decodeLatin1(data);
        _data = data.dup;
    }

    @property string owner() const { return _owner; }
    @property inout(ubyte)[] data() inout { return _data; }

private:

    string _owner;
    ubyte[] _data;
}


class TextFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id.length && header.id[0] == 'T' && header.id != "TXXX");
        super(header);
        enforce(data.length > 0);
        auto encodingByte = data[0];
        data = data[1 .. $];
        _text = decodeString(data, encodingByte);
    }

    @property string text() const { return _text; }

private:

    string _text;
}


class UserTextFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "TXXX");
        super(header);
        enforce(data.length > 0);
        immutable encodingByte = data[0];
        data = data[1 .. $];
        _description = decodeString(data, encodingByte);
        _text = decodeString(data, encodingByte);
    }

    @property string description() const { return _description; }
    @property string text() const { return _text; }

private:

    string _description;
    string _text;
}


class LinkFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id.length && header.id[0] == 'W' && header.id != "WXXX");
        super(header);
        _link = decodeLatin1(data);
    }

    @property string link() const { return _link; }

private:

    string _link;
}


class UserLinkFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "WXXX");
        super(header);
        enforce(data.length > 0);
        immutable encodingByte = data[0];
        data = data[1 .. $];
        _description = decodeString(data, encodingByte);
        _link = decodeLatin1(data);
    }

    @property string description() const { return _description; }
    @property string link() const { return _link; }

private:

    string _description;
    string _link;
}

class MusicCDIdentifierFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "MCDI");
        super(header);
        _data = data.dup;
    }

    @property inout(ubyte)[] data() inout { return _data; }

private:

    ubyte[] _data;
}

class EventTimingCodeFrame : Frame
{
    enum TimeUnit {
        MpegFrame       = 0x01,
        Milliseconds    = 0x02,
    }

    enum EventType {
        Padding                 = 0x00,
        EndOfInitialSilence     = 0x01,
        IntroStart              = 0x02,
        MainPartStart           = 0x03,
        OutroStart              = 0x03,
        OutroEnd                = 0x05,
        VerseStart              = 0x06,
        RefrainStart            = 0x07,
        InterludeStart          = 0x08,
        ThemeStart              = 0x09,
        VariationStart          = 0x0a,
        KeyChange               = 0x0b,
        TimeChange              = 0x0c,
        MomentaryUnwantedNoise  = 0x0d,
        SustainedNoise          = 0x0e,
        SustainedNoiseEnd       = 0x0f,
        IntroEnd                = 0x10,
        MainPartEnd             = 0x11,
        VerseEnd                = 0x12,
        RefrainEnd              = 0x13,
        ThemeEnd                = 0x14,
        Profanity               = 0x15,
        ProfanityEnd            = 0x16,

        StartRerserved1         = 0x17,
        EndRerserved1           = 0xdf,

        NotPredefinedSynch0     = 0xe0,
        NotPredefinedSynch1     = 0xe1,
        NotPredefinedSynch2     = 0xe2,
        NotPredefinedSynch3     = 0xe3,
        NotPredefinedSynch4     = 0xe4,
        NotPredefinedSynch5     = 0xe5,
        NotPredefinedSynch6     = 0xe6,
        NotPredefinedSynch7     = 0xe7,
        NotPredefinedSynch8     = 0xe8,
        NotPredefinedSynch9     = 0xe9,
        NotPredefinedSynchA     = 0xea,
        NotPredefinedSynchB     = 0xeb,
        NotPredefinedSynchC     = 0xec,
        NotPredefinedSynchD     = 0xed,
        NotPredefinedSynchE     = 0xee,
        NotPredefinedSynchF     = 0xef,

        StartRerserved2         = 0xf0,
        EndRerserved2           = 0xfc,

        AudioEnd                = 0xfd,
        AudioFileEnds           = 0xfe,
    }

    struct Event {
        EventType type;
        uint time;
    }

    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        import musictag.utils : decodeBigEndian;

        assert(header.id == "ETCO");
        super(header);
        enforce(data >= 1);
        _timeUnit = cast(TimeUnit)data[0];
        data = data[1 .. $];
        while(data.length >= 5) {
            _events ~= Event(cast(EventType)data[0], decodeBigEndian!uint(data[1 .. 5]));
            data = data[5 .. $];
        }
    }

    @property TimeUnit timeUnit() const { return _timeUnit; }
    @property inout(Event)[] events() inout { return _events; }

private:

    TimeUnit _timeUnit;
    Event[] _events;
}