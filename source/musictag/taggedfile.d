module musictag.taggedfile;

import musictag.tag;

interface TaggedFile
{
    enum Format
    {
        Mpeg,
    }

    @property Format format() const;

    @property inout(Tag) tag() inout;

}
