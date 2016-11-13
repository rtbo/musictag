module musictag.id3v2.builtinframes;

import musictag.id3v2.frame;
import musictag.id3v2.support;
import musictag.utils : decodeBigEndian;

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
        assert(header.id == "ETCO");
        super(header);
        enforce(data.length >= 1);
        _timeUnit = cast(TimeUnit)data[0];
        data = data[1 .. $];
        while(data.length >= 5) {
            _events ~= Event(
                cast(EventType)data[0],
                decodeBigEndian!uint(data[1 .. 5])
            );
            data = data[5 .. $];
        }
    }

    @property TimeUnit timeUnit() const { return _timeUnit; }
    @property inout(Event)[] events() inout { return _events; }

private:

    TimeUnit _timeUnit;
    Event[] _events;
}


class SyncTempoCodes : Frame
{
    enum TimeUnit {
        MpegFrame       = 0x01,
        Milliseconds    = 0x02,
    }

    struct Tempo {
        /// Beats per minutes of this tempo.
        /// Special value 0 indicates beat free
        /// Special value 1 indicates a single beat followed by beat free
        /// >= 2 means actual BPM
        ushort bpm;
        uint time;
    }

    this (ref const FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "SYTC");
        super(header);
        enforce(data.length > 1);
        _timeUnit = cast(TimeUnit)data[0];
        data = data[1 .. $];
        while(data.length >= 5) {
            ushort bpm = data[0];
            if (bpm == 0xff) {
                bpm += data[1];
                data = data[1 .. $];
                if (data.length < 5) break;
            }
            immutable time = decodeBigEndian!uint(data[1 .. 5]);
            _tempos ~= Tempo(bpm, time);
            data = data[5 .. $];
        }
    }

    @property TimeUnit timeUnit() const { return _timeUnit; }
    @property inout(Tempo)[] tempos() inout { return _tempos; }

private:

    TimeUnit _timeUnit;
    Tempo[] _tempos;

}


class LyricsFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "USLT");
        super(header);
        enforce(data.length > 4);
        immutable encodingByte = data[0];
        _lang[] = data[1 .. 4];
        data = data[4 .. $];
        _content = decodeString(data, encodingByte);
        _text = decodeString(data, encodingByte);
    }

    @property ubyte[3] lang() const { return _lang; }
    @property string content() const { return _content; }
    @property string text() const { return _text; }

private:

    ubyte[3] _lang;
    string _content;
    string _text;
}


class SyncLyricsFrame : Frame
{
    enum TimeUnit {
        MpegFrame       = 0x01,
        Milliseconds    = 0x02,
    }

    enum ContentType {
        Other               = 0x00,
        Lyrics              = 0x01,
        TextTranscription   = 0x02,
        MovementName        = 0x03,
        Events              = 0x04,
        Chord               = 0x05,
        Trivia              = 0x06,
        WebPagesURLs        = 0x07,
        ImagesURLs          = 0x08,
    }

    struct TextChunk {
        string text;
        uint time;
    }

    this (const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "SYLT");
        super(header);
        enforce(data.length > 6);
        immutable encodingByte = data[0];
        _lang[] = data[1 .. 4];
        _timeUnit = cast(TimeUnit)data[4];
        _contentType = cast(ContentType)data[5];
        data = data[6 .. $];
        _content = decodeString(data, encodingByte);
        while(data.length > 5) {
            immutable text = decodeString(data, encodingByte);
            if (data.length < 4) return;
            immutable time =  decodeBigEndian!uint(data);
            data = data[4 .. $];
            _chunks ~= TextChunk(text, time);
        }
    }

    @property ubyte[3] lang() const { return _lang; }
    @property TimeUnit timeUnit() const { return _timeUnit; }
    @property ContentType contentType() const { return _contentType; }
    @property string content() const { return _content; }
    @property inout(TextChunk)[] chunks() inout { return _chunks; }

private:

    ubyte[3] _lang;
    TimeUnit _timeUnit;
    ContentType _contentType;
    string _content;
    TextChunk[] _chunks;
}




class CommentsFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "COMM");
        super(header);
        enforce(data.length > 4);
        immutable encodingByte = data[0];
        _lang[] = data[1 .. 4];
        data = data[4 .. $];
        _content = decodeString(data, encodingByte);
        _text = decodeString(data, encodingByte);
    }

    @property ubyte[3] lang() const { return _lang; }
    @property string content() const { return _content; }
    @property string text() const { return _text; }

private:

    ubyte[3] _lang;
    string _content;
    string _text;
}


class RelativeVolumeAdjustFrame : Frame
{
    enum Channel {
        Other            = 0x00,
        MasterVolume     = 0x01,
        FrontRight       = 0x02,
        FrontLeft        = 0x03,
        BackRight        = 0x04,
        BackLeft         = 0x05,
        FrontCentre      = 0x06,
        BackCentre       = 0x07,
        Subwoofer        = 0x08,
    }

    struct ChannelAdjust {
        Channel channel;
        float volumeAdjustment;
        ubyte bitsRepresentingPeak;
        ubyte[] peakVolume;
    }

    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "RVA2");
        super(header);
        _identification = decodeLatin1(data);
        while(data.length > 4)
        {
            immutable ch = cast(Channel)data[0];
            immutable volAdj = decodeBigEndian!short(data[1 .. 3]) / 512f;
            immutable bitsPeak = data[3];
            immutable bytesForPeak = (bitsPeak + 7) / 8;
            ubyte[] peak;
            if (bytesForPeak) {
                if (data.length < bytesForPeak+4) break;
                peak = data[4 .. 4+bytesForPeak].dup;
            }
            _channelAdjusts ~= ChannelAdjust(
                ch, volAdj, bitsPeak, peak
            );
            data = data[4*bytesForPeak .. $];
        }
    }

    @property string identification() const { return _identification; }
    @property const(ChannelAdjust)[] channelAdjusts() const
    {
        return _channelAdjusts;
    }

private:

    string _identification;
    ChannelAdjust[] _channelAdjusts;

}


class EqualisationFrame : Frame
{
    enum InterpMethod
    {
        Band = 0x00,
        Linear = 0x01,
    }

    struct Band {
        float frequency;
        float volumeAdjustment;
    }

    this (const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "EQU2");
        super(header);
        _method = cast(InterpMethod)data[0];
        data = data[1 .. $];
        _identification = decodeLatin1(data);
        while (data.length >= 4)
        {
            _bands ~= Band(
                decodeBigEndian!ushort(data[0 .. 2]) / 2f,
                decodeBigEndian!short(data[2 .. 4]) / 512f,
            );
            data = data[4 .. $];
        }
    }

private:

    InterpMethod _method;
    string _identification;
    Band[] _bands;
}
