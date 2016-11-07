module musictag.id3v2.header;

import std.bitmanip : bitfields;

/// Id3v2 Header (§3.1)
struct Header
{
    /// Fields as described in the header definition §3.1
    @property uint majVersion() const { return _majVersion; }
    /// ditto
    @property uint revision() const { return _revision; }
    /// ditto
    @property bool unsynchronize() const { return _flags.unsynchronize; }
    /// ditto
    @property bool extendedHeader() const { return _flags.extendedHeader; }
    /// ditto
    @property bool experimental() const { return _flags.experimental; }
    /// ditto
    @property bool footer() const { return _flags.footer; }
    /// ditto
    @property size_t tagSize() const { return _tagSize; }

    /// The size of the Id3v2 header (always 10)
    enum size_t size = 10;
    /// The identifier marking the start of the header preceding a Tag
    static @property ubyte[3] identifier() { return ['I', 'D', '3']; }

    /// Parses bytes data into a header.
    /// The data must start with identifier and have length >= size
    static Header parse(const(ubyte)[] data)
    in {
        assert(data.length >= size);
        assert(data[0 .. 3] == identifier);
    }
    body {
        return Header (
            data[3], data[4], cast(Flags)data[5],
            ((data[6] & 0x7f) << 21) | ((data[7] & 0x7f) << 14) |
            ((data[8] & 0x7f) << 7)  | (data[9] & 0x7f)
        );
    }

private:

    struct Flags
    {
        mixin(bitfields!(
            uint, "", 4,
            bool, "footer", 1,
            bool, "experimental", 1,
            bool, "extendedHeader", 1,
            bool, "unsynchronize", 1,
        ));
    }
    static assert(Flags.sizeof == 1);
    unittest {
        Flags f = cast(Flags)0b01110000;
        assert(!f.unsynchronize);
        assert( f.extendedHeader);
        assert( f.experimental);
        assert( f.footer);
    }

    ubyte _majVersion;
    ubyte _revision;
    Flags _flags;
    uint _tagSize;

}