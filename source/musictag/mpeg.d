module musictag.mpeg;

import musictag.tag;
import musictag.id3v2;
import musictag.id3v2.framefactory;
import musictag.support;

import std.stdio : File;


/// Reads a tag from the supplied file and returns it.
/// Returns null if not tag can be read in the file.
/// The FrameFactoryDg parameter is optional. It allows applications to add
/// support for additional frames, not supported by musictag.
Tag readMpegTag(string filename, FrameFactoryDg factoryBuilder=null)
{
    import std.file : exists, isDir;
    import std.stdio : File;
    import std.exception : enforce;

    enforce(exists(filename) && !isDir(filename));
    auto f = File(filename, "rb");

    auto offset = findInFile(f, Id3v2Header.identifier[]);
    if (offset != -1) return new Id3v2Tag(f, offset, factoryBuilder);
    else return null;
}



private:

/// Find the MPEG frame starting at or after startOffset
/// and return offset in file or -1 if no MPEG frame is found
size_t findNextFrame(File f, size_t startOffset=0)
{
    enum bufSize = 4096;
    auto buf = new ubyte[bufSize];
    f.seek(startOffset);
    auto done = cast(size_t)f.tell();
    bool foundFirstByte = false;

    foreach(chunk; f.byChunk(buf))
    {
        if (foundFirstByte) {
            if (isSecondSynchByte(chunk[0])) return done-1;
            else foundFirstByte = false;
        }

        foreach (size_t i; 0 .. chunk.length)
        {
            if (isFirstSynchByte(chunk[i]))
            {
                if (i == chunk.length - 1) foundFirstByte = true;
                else
                {
                    if (isSecondSynchByte(chunk[i+1])) return done + i;
                }
            }
        }

        done += chunk.length;
    }

    return -1;
}


// mpeg frames start with 0b11111111 0b111xxxxx

/// Test if byte is the first byte of an MPEG frame
bool isFirstSynchByte(in ubyte b) pure
{
    return b == 0xff;
}

/// Test if byte is the second byte of an MPEG frame
bool isSecondSynchByte(in byte b) pure
{
    enum mask = 0b11100000;
    return b != 0xff && (b & mask) == mask;
}