module musictag.tag;

import musictag.id3v2;


/// Represents a tag in a file
interface Tag {

    enum Format {
        Id3v2,
    }

    /// Name of the file this tag was issued from.
    @property string filename() const;

    /// Native format of the tag
    @property Format format() const;

    /// Artist / Performer
    @property string artist() const;

    /// Track title
    @property string title() const;

    /// Track number
    @property int track() const;

    /// Part of set (e.g. CD 1/2)
    @property int pos() const;

    /// Composer
    @property string composer() const;

    /// Year
    @property int year() const;

    /// Attached picture (e.g. album cover)
    @property const(byte)[] picture() const;

}