module musictag.id3v2.frame;

import musictag.id3v2.framefactory;

import std.exception : enforce;

abstract class Frame
{
    @property string identifier() const { return _header.id; }
    @property FrameHeader header() { return _header; }

private:
    FrameHeader _header;
}

struct FrameHeader
{
    enum size_t size = 10;  
      
    @property string id() const { return _id; }
    @property size_t frameSize() const { return _frameSize; }
    @property bool tagAlterPreserve() const { return _tagAlterPreserve; }
    @property bool fileAlterPreserve() const { return _fileAlterPreserve; }
    @property bool readOnly() const { return _readOnly; }
    @property bool groupIdentity() const { return _groupIdentity; }
    @property bool compression() const { return _compression; }
    @property bool encryption() const { return _encryption; }
    @property bool dataLengthIdentifier() const { return _dataLengthIdentifier; }
    @property bool unsynchronized() const { return _unsynchronized; }

    static FrameHeader parse(const(ubyte)[] data, uint ver=4)
    {
        assert(ver == 3 || ver == 4);
        enforce(data.length >= 10);
        FrameHeader res;
        res._id = cast(string)(data[0 .. 4].idup);
        if (ver == 3)
        {
            import musictag.utils : decodeBigEndian;
            res._frameSize = decodeBigEndian!uint(data[4 .. 8]);

            res._tagAlterPreserve = cast(bool)(data[8] & 0b1000_0000);
            res._fileAlterPreserve = cast(bool)(data[8] & 0b0100_0000);
            res._readOnly = cast(bool)(data[8] & 0b0010_0000);

            res._compression = cast(bool)(data[9] & 0b1000_0000);
            res._encryption = cast(bool)(data[9] & 0b0100_0000);
            res._groupIdentity = cast(bool)(data[9] & 0b0010_0000);
        }
        else if (ver == 4)
        {
            import musictag.id3v2.synchdata : decodeSynchSafeInt;
            res._frameSize = decodeSynchSafeInt!uint(data[4 .. 8]);

            res._tagAlterPreserve = cast(bool)(data[8] & 0b0100_0000);
            res._fileAlterPreserve = cast(bool)(data[8] & 0b0010_0000);
            res._readOnly = cast(bool)(data[8] & 0b0001_0000);

            res._groupIdentity = cast(bool)(data[9] & 0b0100_0000);
            res._compression = cast(bool)(data[9] & 0b0000_1000);
            res._encryption = cast(bool)(data[9] & 0b0000_0100);
            res._unsynchronized = cast(bool)(data[9] & 0b0000_0010);
            res._dataLengthIdentifier = cast(bool)(data[9] & 0b0000_0001);
        }
        return res;
    }


private:
    
    string _id;
    uint _frameSize;
    bool _tagAlterPreserve;
    bool _fileAlterPreserve;
    bool _readOnly;
    bool _groupIdentity;
    bool _compression;
    bool _encryption;
    bool _dataLengthIdentifier;
    bool _unsynchronized;
}

