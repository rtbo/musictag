module musictag.id3v2.support;

import std.traits : isIntegral;

/// Decodes a tag data that follows the unsynchronization scheme
/// defined in Id3v2.4 structure §6.1.
/// Data may be decoded in place, but no guarantees.
ubyte[] decodeUnsynchronizedTag(ubyte[] data)
{
    import std.array : replace;
    return data.replace!(ubyte, ubyte[], ubyte[])([0xff, 0x00], [0xff]);
}


/// Reads a synch safe integer as defined in Id3v2.4 structure §6.2.
/// Synch safe integers are big endian integer that
/// keep the MSB of each byte cleared.
/// That is a 32 bits synchsafe integer only encode data over 28 bits.
T decodeSynchSafeInt(T)(in ubyte[] data) if (isIntegral!T)
{
    assert(data.length * 7 < T.sizeof * 8);
    T result = 0;
    foreach (i, d; data)
    {
        immutable shift = 7 * (data.length - i - 1);
        result |= (d & 0x7f) << shift;
    }
    return result;
}