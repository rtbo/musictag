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


class ReverbFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "RVRB");
        super(header);
        enforce(data.length >= 12);
        _delayLeft = decodeBigEndian!ushort(data[0 .. 2]);
        _delayRight = decodeBigEndian!ushort(data[2 .. 4]);
        _bouncesLeft = data[4];
        _bouncesRight = data[5];
        _feedbackLeftLeft = data[6];
        _feedbackLeftRight = data[7];
        _feedbackRightRight = data[8];
        _feedbackRightLeft = data[9];
        _premixLeftRight = data[10];
        _premixRightLeft = data[11];
    }

    @property ushort delayLeft() const { return _delayLeft; }
    @property ushort delayRight() const { return _delayRight; }
    @property ubyte bouncesLeft() const { return _bouncesLeft; }
    @property ubyte bouncesRight() const { return _bouncesRight; }
    @property ubyte feedbackLeftLeft() const { return _feedbackLeftLeft; }
    @property ubyte feedbackLeftRight() const { return _feedbackLeftRight; }
    @property ubyte feedbackRightRight() const { return _feedbackRightRight; }
    @property ubyte feedbackRightLeft() const { return _feedbackRightLeft; }
    @property ubyte premixLeftRight() const { return _premixLeftRight; }
    @property ubyte premixRightLeft() const { return _premixRightLeft; }

private:
    ushort _delayLeft;
    ushort _delayRight;
    ubyte _bouncesLeft;
    ubyte _bouncesRight;
    ubyte _feedbackLeftLeft;
    ubyte _feedbackLeftRight;
    ubyte _feedbackRightRight;
    ubyte _feedbackRightLeft;
    ubyte _premixLeftRight;
    ubyte _premixRightLeft;
}


class AttachedPictureFrame : Frame
{
    enum PictureType
    {
        Other               = 0x00,
        fileIcon32x32       = 0x01,
        fileIconOther       = 0x02,
        CoverFront          = 0x03,
        CoverBack           = 0x04,
        LeafletPage         = 0x05,
        Media               = 0x06,
        LeadArtist          = 0x07,
        Artist              = 0x08,
        Conductor           = 0x09,
        Band                = 0x0A,
        Composer            = 0x0B,
        Lyricist            = 0x0C,
        RecordingLocation   = 0x0D,
        DuringRecording     = 0x0E,
        DuringPerformance   = 0x0F,
        MovieCapture        = 0x10,
        BrightColouredFish  = 0x11,  // ??
        Illustration        = 0x12,
        BandLogotype        = 0x13,
        PublisherLogotype   = 0x14,
    }

    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "APIC");
        super(header);
        immutable encodingByte = data[0];
        data = data[1 .. $];
        _mimeType = decodeLatin1(data);
        _pictureType = cast(PictureType)data[0];
        data = data[1 .. $];
        _description = decodeString(data, encodingByte);
        _data = data.dup;
    }

    @property string mimeType() const { return _mimeType; }
    @property PictureType pictureType() const { return _pictureType; }
    @property string description() const { return _description; }
    @property const(ubyte)[] data() const { return _data; }

private:
    string _mimeType;
    PictureType _pictureType;
    string _description;
    ubyte[] _data;
}

class GeneralEncapsulatedObjectFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "GEOB");
        super(header);
        immutable encodingByte = data[0];
        data = data[1 .. $];
        _mimeType = decodeLatin1(data);
        _filename = decodeString(data, encodingByte);
        _description = decodeString(data, encodingByte);
        _objectData = data.dup;
    }

    @property string mimeType() const { return _mimeType; }
    @property string filename() const { return _filename; }
    @property string description() const { return _description; }
    @property const(ubyte)[] objectData() const { return _objectData; }

private:
    string _mimeType;
    string _filename;
    string _description;
    ubyte[] _objectData;
}


class PlayCounterFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "PCNT");
        super(header);
        _count = decodeBigEndian!size_t(data);
    }

    @property size_t count() const { return _count; }

private:
    size_t _count;
}


class PopularimeterFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "POPM");
        super(header);

        _email = decodeLatin1(data);
        _rating = data[0];
        _count = decodeBigEndian!size_t(data[1 .. $]);
    }

    @property string email() const { return _email; }
    @property ubyte rating() const { return _rating; }
    @property size_t count() const { return _count; }

private:
    string _email;
    ubyte _rating;
    size_t _count;
}


class AudioEncryptionFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "AENC");
        super(header);
        _owner = decodeLatin1(data);
        enforce(data.length > 4);
        _previewStart = decodeBigEndian!ushort(data[0 .. 2]);
        _previewLength = decodeBigEndian!ushort(data[2 .. 4]);
        _encryptionInfo = data[4 .. $].dup;
    }

    @property string owner() const { return _owner; }
    @property ushort previewStart() const { return _previewStart; }
    @property ushort previewLength() const { return _previewLength; }
    @property const(ubyte)[] encryptionInfo() const {
        return _encryptionInfo;
    }

private:
    string _owner;
    ushort _previewStart;
    ushort _previewLength;
    ubyte[] _encryptionInfo;
}


class CommercialFrame : Frame
{
    import std.datetime : Date;

    enum ReceivedAs
    {
        Other                               = 0x00,
        StandardCDAlbumWithOtherSongs       = 0x01,
        CompressedAudioOnCD                 = 0x02,
        FileOverTheInternet                 = 0x03,
        StreamOverTheInternet               = 0x04,
        AsNoteSheets                        = 0x05,
        AsNoteSheetsInABookWithOtherSheets  = 0x06,
        MusicOnOtherMedia                   = 0x07,
        NonMusicalMerchandise               = 0x08,
    }

    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        import std.conv : to;

        assert(header.id == "COMR");
        super(header);
        enforce(data.length >= 15);
        immutable ubyte encodingByte = data[0];
        data = data[1 .. $];
        _price = decodeLatin1(data);
        enforce(data.length > 13);
        const date = cast(const(char)[])data[0 .. 8];
        _validUntil = Date(
            date[0 .. 4].to!int, date[4 .. 6].to!int, date[6 .. 8].to!int
        );
        data = data[8 .. $];
        _contact = decodeLatin1(data);
        enforce(data.length >= 4);
        _receivedAs = cast(ReceivedAs)data[0];
        data = data[1 .. $];
        _seller = decodeString(data, encodingByte);
        _description = decodeString(data, encodingByte);
        _pictureMimeType = decodeLatin1(data);
        _pictureData = data.dup;
    }

    @property string price() const { return _price; }
    @property Date validUntil() const { return _validUntil; }
    @property string contact() const { return _contact; }
    @property ReceivedAs receivedAs() const { return _receivedAs; }
    @property string seller() const { return _seller; }
    @property string description() const { return _description; }
    @property string pictureMimeType() const { return _pictureMimeType; }
    @property const(ubyte)[] pictureData() const { return _pictureData; }


private:

    string _price;
    Date _validUntil;
    string _contact;
    ReceivedAs _receivedAs;
    string _seller;
    string _description;
    string _pictureMimeType;
    ubyte[] _pictureData;
}


class PrivateFrame : Frame
{
    this(const ref FrameHeader header, const(ubyte)[] data)
    {
        assert(header.id == "PRIV");
        super(header);
        _owner = decodeLatin1(data);
        _data = data.dup;
    }

    @property string owner() const { return _owner; }
    @property const(ubyte)[] data() const {
        return _data;
    }

private:
    string _owner;
    ubyte[] _data;
}
