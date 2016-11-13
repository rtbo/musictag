module musictag.id3v2.framefactory;

import musictag.id3v2.frame;
import musictag.id3v2.header;
import musictag.id3v2.builtinframes;


/// Delegate that can return a FrameFactory based on the
/// tag header. This allows applications to provide different
/// factories based on the tag version
alias FrameFactoryDg = FrameFactory delegate(Header header);

/// Builds music default frame factory
FrameFactory defaultFrameFactory(Header header)
{
    return new DefaultFrameFactory(header.majVersion);
}

/// Dynamic frame builder that can be supplied
/// by applications through frame factory build delegate
interface FrameFactory
{
    /// Create a frame with header, data, and id3v2 version
    Frame createFrame(const ref FrameHeader header, const(ubyte)[] data);
}

private:

class DefaultFrameFactory : FrameFactory
{
    this(uint ver)
    {
        this.ver = ver;
    }

    Frame createFrame(const ref FrameHeader header, const(ubyte)[] data)
    {
        import std.exception : enforce;

        enforce(header.id.length == 4);
        if (header.id == "UFID") return new UFIDFrame(header, data);
        else if (header.id[0] == 'T' && header.id != "TXXX")
            return new TextFrame(header, data);
        else if (header.id == "TXXX")
            return new UserTextFrame(header, data);
        else if (header.id[0] == 'W' && header.id != "WXXX")
            return new LinkFrame(header, data);
        else if (header.id == "WXXX")
            return new UserLinkFrame(header, data);
        else if (header.id == "MCDI")
            return new MusicCDIdentifierFrame(header, data);
        else if (header.id == "ETCO")
            return new EventTimingCodeFrame(header, data);
        else if (header.id == "SYTC")
            return new SyncTempoCodes(header, data);
        else if (header.id == "USLT")
            return new LyricsFrame(header, data);
        else if (header.id == "SYLT")
            return new SyncLyricsFrame(header, data);
        else if (header.id == "COMM")
            return new CommentsFrame(header, data);
        else if (header.id == "RVA2")
            return new RelativeVolumeAdjustFrame(header, data);
        else if (header.id == "EQU2")
            return new EqualisationFrame(header, data);
        return null;
    }

    // id3v2 version
    uint ver;
}
