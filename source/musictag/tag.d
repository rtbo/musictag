module musictag.tag;

import musictag.id3v2;


/// Represents a tag in a file
interface Tag {

    enum Format {
        Id3v2,
        Vorbis,
    }

    /// Name of the file this tag was issued from.
    /// Might return empty string if e.g. the tag is issued
    /// from a network stream
    @property string filename() const;

    /// Native format of the tag
    @property Format format() const;

    /// Artist / Performer
    @property string artist() const;

    /// Track title
    @property string title() const;

    /// Album name
    @property string album() const;

    /// Track number
    /// Returns -1 if the track frame does not exist
    @property int track() const;

    /// Part of set (e.g. CD 1/2)
    /// Returns -1 if the frame does not exist
    @property int pos() const;

    /// Composer
    @property string composer() const;

    /// Year
    @property int year() const;

    /// Attached picture (e.g. album cover)
    @property const(ubyte)[] picture() const;

}