module musictag.id3v2.support;

import std.traits : isIntegral;
import std.exception : enforce;

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


// String decoding functions

/// Decodes a null terminating string with the given encoding byte
/// (specs/id3v2.4.0-structure.txt §4).
/// Advances data to the byte after the null character and returns the string
/// encoded in utf-8.
string decodeString(ref const(ubyte)[] data, in ubyte encodingByte)
{
    switch(encodingByte)
    {
        case 0: return decodeLatin1(data);
        case 1: return decodeUTF16BOM(data);
        case 2: return decodeUTF16BE(data);
        case 3: {
            import std.algorithm : countUntil;
            immutable nullPos = data.countUntil(0);
            enforce (nullPos != -1);
            string s = cast(string)(data[0 .. nullPos]);
            data = data[nullPos+1 .. $];
            return s;
        }
        default: {
            throw new Exception("Invalid ID3v2 text encoding byte");
        }
    }
}

/// Decodes a null terminated latin-1 string.
/// The function will update the beginning of the range to the first byte
/// after the null character, and return the decoded string
string decodeLatin1(ref const(ubyte)[] data)
{
    import std.utf : encode;

    string res; // do not pre-alloc with data.length: data could be the whole tag!
    auto d = data;  // local copy to avoid cache mess
    char[4] buf = void;
    
    while (d.length && d[0] != 0)
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

/// Decodes a null terminated UTF16 string starting with BOM.
/// Throws if string does not start with BOM or if null char is not found.
/// The function will advance the data range to the first byte
/// after the null character, and return the string encoded as utf-8.
string decodeUTF16BOM(ref const(ubyte)[] data)
{
    version(BigEndian)
    {
        enum ubyte[] nativeBOM = [0xfe, 0xff];
        enum ubyte[] reverseBOM = [0xff, 0xfe];
    }
    else
    {
        enum ubyte[] nativeBOM = [0xff, 0xfe];
        enum ubyte[] reverseBOM = [0xfe, 0xff];
    }

    enforce(data.length >= 4); // BOM + null
    auto bom = data[0 .. 2];
    data = data[2 .. $];

    if (bom == nativeBOM)
    {
        return decodeNativeUTF16(data);
    }
    else if (bom == reverseBOM)
    {
        return decodeReverseUTF16(data);
    }
    else
    {
        throw new Exception("decodeUTF16BOM: No BOM found.");
    }
}



/// Decodes a null terminated big endian UTF16 string.
/// Throws if null char is not found.
/// The function will advance the data range to the first byte
/// after the null character, and return the string encoded as utf-8.
string decodeUTF16BE(ref const(ubyte)[] data)
{
    version(BigEndian)
    {
        return decodeNativeUTF16(data);
    }
    else
    {
        return decodeReverseUTF16(data);
    }
}

private:

string decodeNativeUTF16(ref const(ubyte)[] data)
{
    import std.utf : decode, encode;

    auto wptr = cast(const(wchar)*)data.ptr;
    auto w = wptr[0 .. data.length/2];

    assert(w.length >= 1);

    string res;
    char[4] buf = void;
    size_t index = 0;

    while (index < w.length && w[index] != 0)
    {
        immutable dchar c = decode(w, index); 
        immutable len = encode(buf, c);
        res ~= buf[0 .. len];
    }

    enforce(index < w.length && w[index] == 0);
    data = data[index*2 .. $];
    return res;
}

string decodeReverseUTF16(ref const(ubyte)[] data)
{    
    import std.uni : isSurrogateHi;
    import std.utf : decodeFront, encode;


    string res;
    char[4] buf = void;
    wchar[2] wbuf = void;
    size_t units = 1;
    auto d = data;

    while (d.length >= 2 && d[0] != 0 && d[1] != 0)
    {
        wbuf[0] = (d[1] << 8) | d[0];
        if (isSurrogateHi(wbuf[0]))
        {
            units++;
            d = d[2 .. $];
            continue;
        }
        auto range = wbuf[0 .. units];
        immutable dchar c = decodeFront(range);
        enforce(!range.length); // or assert?
        d = d[2 .. $];
        units = 1;
    }
    
    enforce(d.length >= 2 && d[0] == 0 && d[1] == 0);
    data = d[2 .. $]; // eat null char and assign
    return res;
}