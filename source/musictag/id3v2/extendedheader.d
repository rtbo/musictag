module musictag.id3v2.extendedheader;

// TODO: parse the whole extended header.

/// Id3v2 extended header common implementation for v2.3 and v2.4 (§3.1 in both spec)
class ExtendedHeader
{

    this (const(ubyte)[] data, uint ver)
    {
        assert(ver == 3 || ver == 4);
        if (ver == 3)
        {
            import musictag.support : decodeBigEndian;
            // In id3v2.3, the size field excludes itself
            _size = decodeBigEndian!size_t(data[0 .. 4]) + 4;
        }
        else
        {
            import musictag.id3v2.support : decodeSynchSafeInt;
            _size = decodeSynchSafeInt!size_t(data[0 .. 4]);
        }
    }

    /// the size of the whole header
    @property size_t size() const { return _size; }


private:

    size_t _size;
}