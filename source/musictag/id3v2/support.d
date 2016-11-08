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


/// Decodes a null terminated latin-1 string.
/// The function will update the beginning of the range to the first byte
/// after the null character, and return the decoded string
string decodeLatin1(ref const(ubyte)[] data)
{
    import std.exception : enforce;
    import std.utf : encode;

    string res; // do not pre-alloc with data.length: data could be the whole tag!
    auto d = data;  // local copy to avoid cache mess
    char[4] buf;

    while (d.length || d[0] != 0)
    {
        immutable dchar c = d[0]; // latin-1 is unicode code points from 0 to 255
        immutable len = encode(buf, c);
        res ~= buf[0 .. len];
        d = d[1 .. $];
    }

    enforce(d.length); // check that we actually hit the null char
    data = d[1 .. $]; // eat null and assign
    return res;
}

}
