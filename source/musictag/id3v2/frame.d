module musictag.id3v2.frame;


interface Frame
{
    @property string identifier() const;

    static size_t headerSize(uint ver=4)
    {
        assert(ver == 3 || ver == 4);
        return 10;
    }

    static struct Header
    {
        string id;
        size_t size;
    }
}


Frame readFrame(const(ubyte)[] data, uint ver=4)
{
    return null;
}
