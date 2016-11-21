module musictag.id3v2.support;

import musictag.bitstream;

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



/// Transcodes the give bytes from the given encoding byte to utf-8.
/// (specs/id3v2.4.0-structure.txt §4).
/// Will read chars until a null char is found or until range exhausts.
/// Do not check for valid Unicode.
string readString(R)(ref R range, in ubyte encodingByte)
{
    switch(encodingByte)
    {
        case 0: return range.readStringLatin1();
        case 1: return range.readStringUtf16Bom();
        case 2: return range.readStringUtf16BE();
        case 3: return range.readStringUtf8();
        default: {
            throw new Exception("Invalid ID3v2 text encoding byte");
        }
    }
}

/// Transcodes the give bytes from the given encoding byte to utf-8.
/// (specs/id3v2.4.0-structure.txt §4).
/// Will attempt to read up to len chars and stop if range exhausts.
/// Do not check for valid Unicode.
string readString(R)(ref R range, in ubyte encodingByte, in size_t len)
{
    switch(encodingByte)
    {
        case 0: return range.readStringLatin1(len);
        case 1: return range.readStringUtf16Bom(len);
        case 2: return range.readStringUtf16BE(len);
        case 3: return range.readStringUtf8(len);
        default: {
            throw new Exception("Invalid ID3v2 text encoding byte");
        }
    }
}


// String decoding functions

/// Transcodes the give bytes from the given encoding byte to utf-8.
/// (specs/id3v2.4.0-structure.txt §4).
/// The string can be null terminated. In this case data is advanced
/// to the byte after the null character. Otherwise, data is advanced
/// until its end.
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

/// Transcodes a latin-1 string to utf-8.
/// The string can be null terminated. In this case data is advanced
/// to the byte after the null character. Otherwise, data is advanced
/// until its end.
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

    if (d.length) data = d[1 .. $];
    else data = d;

    return res;
}

/// Transcodes a UTF-16 string with BOM to utf-8.
/// The string can be null terminated. In this case data is advanced
/// to the byte after the null character. Otherwise, data is advanced
/// until its end.
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

    enforce(data.length >= 2); // BOM
    const bom = data[0 .. 2];
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

    string res;
    char[4] buf = void;
    size_t index = 0;

    while (index < w.length && w[index] != 0)
    {
        immutable dchar c = decode(w, index);
        immutable len = encode(buf, c);
        res ~= buf[0 .. len];
    }

    if (index < w.length) ++index; // eat null
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
        immutable len = encode(buf, c);
        res ~= buf[0 .. len];
        d = d[2 .. $];
        units = 1;
    }

    enforce(d.length >= 2 && d[0] == 0 && d[1] == 0);
    data = d[2 .. $]; // eat null char and assign
    return res;
}
