module make_test_wav;

import std.typecons : Flag, Yes, No;
import std.range.primitives;
import std.array;
import std.stdio;

alias Bytes = immutable(ubyte)[];

void putInteger(T, Flag!"msbFirst" byteOrder, R)(ref R output, in T num)
if (isOutputRange!(R, ubyte))
{
    foreach(i; 0 .. T.sizeof)
    {
        immutable shift = 8 * (
            byteOrder == Yes.msbFirst ? (T.sizeof - (i + 1)) : i
        );
        immutable mask = 0xff << shift;
        immutable b = T(num & mask) >>> shift;
        assert(b <= 255);
        put(output, cast(ubyte)b);
    }
}

void putLittleEndian(T, R)(ref R output, in T num)
if (isOutputRange!(R, ubyte))
{
    putInteger!(T, No.msbFirst)(output, num);
}

void putBigEndian(T, R)(ref R output, in T num)
if (isOutputRange!(R, ubyte))
{
    putInteger!(T, Yes.msbFirst)(output, num);
}

unittest
{
    auto output = appender!(ubyte[]);
    putBigEndian(output, 0xaabbccdd);
    assert(output.data == [0xaa, 0xbb, 0xcc, 0xdd]);
}
unittest
{
    auto output = appender!(ubyte[]);
    putLittleEndian(output, 0xaabbccdd);
    assert(output.data == [0xdd, 0xcc, 0xbb, 0xaa]);
}


void putWAVHeader(R)(ref R output, uint sampleRate, uint samples,
                     ushort channels, ushort bps)
if (isOutputRange!(R, ubyte))
{
    // http://soundfile.sapp.org/doc/WaveFormat/

    immutable subchunkSize1 = 16;
    immutable subchunkSize2 = samples*channels*bps/8;
    immutable chunkSize = subchunkSize1 + subchunkSize2 + 20;

    put(output, cast(Bytes)"RIFF");
    putLittleEndian!uint(output, chunkSize);
    put(output, cast(Bytes)"WAVE");

    put(output, cast(Bytes)"fmt ");
    putLittleEndian!uint(output, subchunkSize1);
    putLittleEndian!ushort(output, 1);
    putLittleEndian!ushort(output, channels);
    putLittleEndian!uint(output, sampleRate);
    putLittleEndian!uint(output, sampleRate*channels*bps/8);
    putLittleEndian!ushort(output, cast(ushort)(channels*bps/8));
    putLittleEndian!ushort(output, bps);

    put(output, cast(Bytes)"data");
    putLittleEndian!uint(output, subchunkSize2);
}

void putLPCM8sample(R)(ref R output, float sample)
if (isOutputRange!(R, ubyte))
{
    put(output, cast(ubyte)(255 * ((sample + 1f)/2f)));
}

void main(string[] args)
{
    import std.math;

    // emits a 1 sec A sine over 2 channels with a PI/2 phasing
    immutable freq = 440;
    immutable duration = 1;
    immutable sampleRate = 22050;

    immutable numPeriods = duration * freq;
    immutable period = 1f / float(freq);


    auto output = appender!(ubyte[]);

    // WAV LPCM audio file, 8pbs
    putWAVHeader(output, sampleRate, duration*sampleRate, 2, 8);

    // LPCM output, 8 bps
    foreach(i; 0 .. duration*sampleRate)
    {
        immutable float phase = i * freq * 2 * PI / sampleRate;
        immutable float leftSample = sin(phase);
        immutable float rightSample = sin(phase + (PI / 2f));
        putLPCM8sample(output, leftSample);
        putLPCM8sample(output, rightSample);
    }

    import std.file : write;
    assert(args.length > 1);
    write(args[1], output.data);
}
