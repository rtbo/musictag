module musictag.tag;

import musictag.id3v2;

interface Tag {

    enum Format {
        Id3v2,
    }

    @property string filename() const;
    @property Format format() const;

    @property string frame(string identifier) const;

    @property string artist() const;
    @property string title() const;
    @property int track() const;
    @property string composer() const;
    @property string year() const;
    @property const(byte)[] picture() const;

}