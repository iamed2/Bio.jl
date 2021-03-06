module TestIntervals

using Base.Test
using Bio.Intervals
using Bio.Seq
using Distributions
using TestFunctions
using YAML
import ColorTypes: RGB
import FixedPointNumbers: N0f8

# Test that an array of intervals is well ordered
function Intervals.isordered{I <: Interval}(intervals::Vector{I})
    for i = 2:length(intervals)
        if !Intervals.isordered(intervals[i-1], intervals[i])
            return false
        end
    end
    return true
end


# Generate an array of n random Interval{Int} object. With sequence names
# samples from seqnames, and intervals drawn to lie in [1, maxpos].
function random_intervals(seqnames, maxpos::Int, n::Int)
    seq_dist = Categorical(length(seqnames))
    strand_dist = Categorical(2)
    length_dist = Normal(1000, 1000)

    intervals = Array(Interval{Int}, n)
    for i in 1:n
        intlen = maxpos
        while intlen >= maxpos || intlen <= 0
            intlen = ceil(Int, rand(length_dist))
        end
        first = rand(1:maxpos-intlen)
        last = first + intlen - 1
        strand = rand(strand_dist) == 1 ? STRAND_POS : STRAND_NEG
        intervals[i] = Interval{Int}(seqnames[rand(seq_dist)],
                                     first, last, strand, i)
    end
    return intervals
end


# A simple interval intersection implementation to test against.
function simple_intersection(intervals_a, intervals_b)
    sort!(intervals_a)
    sort!(intervals_b)

    intersections = Any[]

    i = 1
    j = 1
    while i <= length(intervals_a) && j <= length(intervals_b)
        ai = intervals_a[i]
        bj = intervals_b[j]

        if isless(ai.seqname, bj.seqname) ||
           (ai.seqname == bj.seqname && ai.last < bj.first)
            i += 1
        elseif isless(bj.seqname, ai.seqname) ||
               (ai.seqname == bj.seqname && bj.last < ai.first)
            j += 1
        else
            k = j
            while k <= length(intervals_b) && intervals_b[k].first <= ai.last
                if isoverlapping(ai, intervals_b[k])
                    push!(intersections, (ai, intervals_b[k]))
                end
                k += 1
            end
            i += 1
        end
    end

    return intersections
end


function simple_coverage(intervals)
    seqlens = Dict{AbstractString, Int}()
    for interval in intervals
        if get(seqlens, interval.seqname, -1) < interval.last
            seqlens[interval.seqname] = interval.last
        end
    end

    covarrays = Dict{AbstractString, Vector{Int}}()
    for (seqname, seqlen) in seqlens
        covarrays[seqname] = zeros(Int, seqlen)
    end

    for interval in intervals
        arr = covarrays[interval.seqname]
        for i in interval.first:interval.last
            arr[i] += 1
        end
    end

    covintervals = Interval{UInt32}[]
    for (seqname, arr) in covarrays
        i = j = 1
        while i <= length(arr)
            if arr[i] > 0
                j = i + 1
                while j <= length(arr) && arr[j] == arr[i]
                    j += 1
                end
                push!(covintervals,
                      Interval{UInt32}(seqname, i, j - 1, STRAND_BOTH, arr[i]))
                i = j
            else
                i += 1
            end
        end
    end

    return covintervals
end

@testset "Strand" begin
    @testset "Constructor" begin
        @test Strand('?') === STRAND_NA
        @test Strand('+') === STRAND_POS
        @test Strand('-') === STRAND_NEG
        @test Strand('.') === STRAND_BOTH
        @test_throws Exception Strand('x')
    end

    @testset "Conversion" begin
        @test convert(Strand, '?') === STRAND_NA
        @test convert(Strand, '+') === STRAND_POS
        @test convert(Strand, '-') === STRAND_NEG
        @test convert(Strand, '.') === STRAND_BOTH

        @test convert(Char, STRAND_NA) === '?'
        @test convert(Char, STRAND_POS) === '+'
        @test convert(Char, STRAND_NEG) === '-'
        @test convert(Char, STRAND_BOTH) === '.'
    end

    @testset "Order" begin
        @test STRAND_NA < STRAND_POS < STRAND_NEG < STRAND_BOTH
    end

    @testset "Show" begin
        @testset "show" begin
            buf = IOBuffer()
            for s in [STRAND_NA, STRAND_POS, STRAND_NEG, STRAND_BOTH]
                show(buf, s); print(buf, " ")
            end
            @test takebuf_string(buf) == "STRAND_NA STRAND_POS STRAND_NEG STRAND_BOTH "
        end

        @testset "print" begin
            buf = IOBuffer()
            for s in [STRAND_NA, STRAND_POS, STRAND_NEG, STRAND_BOTH]
                print(buf, s)
            end
            @test takebuf_string(buf) == "?+-."
        end
    end
end

@testset "Interval" begin
    @testset "Constructor" begin
        i = Interval("chr1", 10, 20)
        @test seqname(i) == "chr1"
        @test leftposition(i) == 10
        @test rightposition(i) == 20
        @test strand(i) == STRAND_BOTH
        @test i == Interval("chr1", 10:20)

        i1 = Interval("chr1", 10, 20, '+')
        i2 = Interval("chr1", 10, 20, STRAND_POS)
        @test i1 == i2
        @test i1 == Interval("chr1", 10:20, '+')

        i1 = Interval("chr2", 5692667, 5701385, '+',        "SOX11")
        i2 = Interval("chr2", 5692667, 5701385, STRAND_POS, "SOX11")
        @test i1 == i2
        @test i1 == Interval("chr2", 5692667:5701385, '+', "SOX11")
    end
end

@testset "IntervalCollection" begin

    @testset "Insertion/Iteration" begin
        n = 100000
        intervals = random_intervals(["one", "two", "three"], 1000000, n)
        ic = IntervalCollection{Int}()

        @test isempty(ic)
        @test collect(Interval{Int}, ic) == Interval{Int}[]

        for interval in intervals
            push!(ic, interval)
        end
        @test Intervals.isordered(collect(Interval{Int}, ic))
    end


    @testset "Intersection" begin
        n = 1000
        srand(1234)
        intervals_a = random_intervals(["one", "two", "three"], 1000000, n)
        intervals_b = random_intervals(["one", "three", "four"], 1000000, n)

        # empty versus empty
        ic_a = IntervalCollection{Int}()
        ic_b = IntervalCollection{Int}()
        @test collect(eachoverlap(ic_a, ic_b)) == Any[]

        # empty versus non-empty
        for interval in intervals_a
            push!(ic_a, interval)
        end

        @test collect(eachoverlap(ic_a, ic_b)) == Any[]
        @test collect(eachoverlap(ic_b, ic_a)) == Any[]

        # non-empty versus non-empty
        for interval in intervals_b
            push!(ic_b, interval)
        end

        @test sort(collect(eachoverlap(ic_a, ic_b))) == sort(simple_intersection(intervals_a, intervals_b))
    end


    @testset "Show" begin
        ic = IntervalCollection{Int}()
        show(DevNull, ic)

        push!(ic, Interval{Int}("one", 1, 1000, STRAND_POS, 0))
        show(DevNull, ic)

        intervals = random_intervals(["one", "two", "three"], 1000000, 100)
        for interval in intervals
            push!(ic, interval)
        end
        show(DevNull, ic)

        show(DevNull, STRAND_NA)
        show(DevNull, STRAND_POS)
        show(DevNull, STRAND_NEG)
        show(DevNull, STRAND_BOTH)
    end
end


@testset "Alphanumeric Sorting" begin
    @test sort(["b", "c" ,"a"], lt=Intervals.alphanum_isless) == ["a", "b", "c"]
    @test sort(["a10", "a2" ,"a1"], lt=Intervals.alphanum_isless) == ["a1", "a2", "a10"]
    @test sort(["a10a", "a2c" ,"a3b"], lt=Intervals.alphanum_isless) == ["a2c", "a3b", "a10a"]
    @test sort(["a3c", "a3b" ,"a3a"], lt=Intervals.alphanum_isless) == ["a3a", "a3b", "a3c"]
    @test sort(["a1ac", "a1aa" ,"a1ab"], lt=Intervals.alphanum_isless) == ["a1aa", "a1ab", "a1ac"]

    @test Intervals.alphanum_isless("aa", "aa1")
    @test !Intervals.alphanum_isless("aa1", "aa")

    @test sort(["ac3", "aa", "ab", "aa1", "ac", "ab2"], lt=Intervals.alphanum_isless) ==
        ["aa", "aa1", "ab", "ab2", "ac", "ac3"]
end


@testset "IntervalStream" begin
    @testset "StreamBuffer" begin
        ref = Int[]
        sb = Intervals.StreamBuffer{Int}()
        @test isempty(sb)
        @test length(sb) == 0
        @test_throws Exception shift!(sb)

        ref_shifts = Int[]
        sb_shifts = Int[]

        for i in 1:10000
            if !isempty(ref) && rand() < 0.3
                push!(ref_shifts, shift!(ref))
                push!(sb_shifts, shift!(sb))
            else
                x = rand(Int)
                push!(ref, x)
                push!(sb, x)
            end
        end

        @test length(sb) == length(ref)
        @test [sb[i] for i in 1:length(sb)] == ref
        @test ref_shifts == sb_shifts
        @test_throws BoundsError sb[0]
        @test_throws BoundsError sb[length(sb) + 1]
    end

    @testset "Intersection" begin
        n = 1000
        srand(1234)
        intervals_a = random_intervals(["one", "two", "three"], 1000000, n)
        intervals_b = random_intervals(["one", "three", "four"], 1000000, n)

        ic_a = IntervalCollection{Int}()
        ic_b = IntervalCollection{Int}()

        for interval in intervals_a
            push!(ic_a, interval)
        end

        for interval in intervals_b
            push!(ic_b, interval)
        end

        # non-empty versus non-empty, stream intersection
        it = Intervals.IntervalStreamIntersectIterator{Int, Int,
                IntervalCollection{Int}, IntervalCollection{Int}}(
                ic_a, ic_b, isless)

        @test sort(collect(it)) == sort(simple_intersection(intervals_a, intervals_b))

        # Interesction edge cases: skipping over whole sequences
        typealias SimpleIntersectIterator
            Intervals.IntervalStreamIntersectIterator{Void, Void,
                Vector{Interval{Void}}, Vector{Interval{Void}}}

        it = SimpleIntersectIterator(
            [Interval("a", 1, 100, STRAND_POS, nothing), Interval("c", 1, 100, STRAND_POS, nothing)],
            [Interval("a", 1, 100, STRAND_POS, nothing), Interval("b", 1, 100, STRAND_POS, nothing)],
            isless)
        @test length(collect(it)) == 1

        it = SimpleIntersectIterator(
            [Interval("c", 1, 100, STRAND_POS, nothing), Interval("d", 1, 100, STRAND_POS, nothing)],
            [Interval("b", 1, 100, STRAND_POS, nothing), Interval("d", 1, 100, STRAND_POS, nothing)],
            isless)
        @test length(collect(it)) == 1

        # unsorted streams are not allowed
        @test_throws Exception begin
            it = SimpleIntersectIterator(
                [Interval("b", 1, 1000, STRAND_POS, nothing),
                 Interval("a", 1, 1000, STRAND_POS, nothing)],
                [Interval("a", 1, 1000, STRAND_POS, nothing),
                 Interval("b", 1, 1000, STRAND_POS, nothing)], isless)
            collect(it)
        end

        @test_throws Exception begin
            it = SimpleIntersectIterator(
                [Interval("a", 1, 1000, STRAND_POS, nothing),
                 Interval("a", 500, 1000, STRAND_POS, nothing),
                 Interval("a", 400, 2000, STRAND_POS, nothing)],
                [Interval("a", 1, 1000, STRAND_POS, nothing),
                 Interval("b", 1, 1000, STRAND_POS, nothing)], isless)
            collect(it)
        end
    end


    @testset "IntervalStream Intersection" begin
        n = 1000
        srand(1234)
        intervals_a = random_intervals(["one", "two", "three"], 1000000, n)
        intervals_b = random_intervals(["one", "two", "three"], 1000000, n)

        ic_a = IntervalCollection{Int}()
        ic_b = IntervalCollection{Int}()

        for interval in intervals_a
            push!(ic_a, interval)
        end

        for interval in intervals_b
            push!(ic_b, interval)
        end

        ItType = Intervals.IntervalStreamIntersectIterator{Int, Int,
            IntervalCollection{Int}, IntervalCollection{Int}}

        @test sort(collect(ItType(ic_a, ic_b, isless))) == sort(simple_intersection(intervals_a, intervals_b))
    end

    @testset "IntervalStream Coverage" begin
        n = 10000
        srand(1234)
        intervals = random_intervals(["one", "two", "three"], 1000000, n)

        ic = IntervalCollection{Int}()
        for interval in intervals
            push!(ic, interval)
        end

        @test sort(simple_coverage(intervals)) == sort(collect(coverage(ic)))
    end

    @testset "eachoverlap" begin
        # TODO: more tests

        i = Interval("chr1", 1, 10)
        intervals_a = typeof(i)[]
        @test length(collect(eachoverlap(intervals_a, intervals_a))) == 0

        intervals_a = [Interval("chr1", 1, 10)]
        intervals_b = eltype(intervals_a)[]
        @test length(collect(eachoverlap(intervals_a, intervals_b))) == 0
        @test length(collect(eachoverlap(intervals_b, intervals_a))) == 0

        intervals_a = [Interval("chr1", 1, 10)]
        @test length(collect(eachoverlap(intervals_a, intervals_a))) == 1

        intervals_a = [Interval("chr1", 1, 10)]
        intervals_b = [Interval("chr2", 1, 10)]
        @test length(collect(eachoverlap(intervals_a, intervals_b))) == 0
        @test length(collect(eachoverlap(intervals_b, intervals_a))) == 0

        intervals_a = [Interval("chr1", 1, 10)]
        intervals_b = [Interval("chr1", 11, 15)]
        @test length(collect(eachoverlap(intervals_a, intervals_b))) == 0
        @test length(collect(eachoverlap(intervals_b, intervals_a))) == 0

        intervals_a = [Interval("chr1", 11, 15)]
        intervals_b = [Interval("chr1", 1, 10), Interval("chr1", 12, 13)]
        @test length(collect(eachoverlap(intervals_a, intervals_b))) == 1
        @test length(collect(eachoverlap(intervals_b, intervals_a))) == 1

        intervals_a = [Interval("chr1", 1, 2), Interval("chr1", 2, 5), Interval("chr2", 1, 10)]
        intervals_b = [Interval("chr1", 1, 2), Interval("chr1", 2, 3), Interval("chr2", 1, 2)]
        @test length(collect(eachoverlap(intervals_a, intervals_b))) == 5
        @test length(collect(eachoverlap(intervals_b, intervals_a))) == 5

        intervals_a = [Interval("chr1", 1, 2), Interval("chr1", 3, 5), Interval("chr2", 1, 10)]
        @test length(collect(eachoverlap(intervals_a, intervals_a))) == 3

        # compare generic and specific eachoverlap methods
        intervals_a = [Interval("chr1", 1, 2), Interval("chr1", 1, 3), Interval("chr1", 5, 9),
                       Interval("chr2", 1, 5), Interval("chr2", 6, 6), Interval("chr2", 6, 8)]
        intervals_b = intervals_a
        ic_a = IntervalCollection(intervals_a)
        ic_b = IntervalCollection(intervals_b)
        iter1 = eachoverlap(intervals_a, intervals_b)
        iter2 = eachoverlap(intervals_a, ic_b)
        iter3 = eachoverlap(ic_a, intervals_b)
        iter4 = eachoverlap(ic_a, ic_b)
        @test collect(iter1) == collect(iter2) == collect(iter3) == collect(iter4)
    end
end


@testset "Interval Parsing" begin
    @testset "BED" begin
        @testset "Record" begin
            record = BED.Record(b"chr1\t17368\t17436")
            @test BED.chrom(record) == "chr1"
            @test BED.chromstart(record) === 17369
            @test BED.chromend(record) === 17436
            @test !BED.hasname(record)
            @test !BED.hasscore(record)
            @test !BED.hasstrand(record)
            @test !BED.hasthickstart(record)
            @test !BED.hasthickend(record)
            @test !BED.hasitemrgb(record)
            @test !BED.hasblockcount(record)
            @test !BED.hasblocksizes(record)
            @test !BED.hasblockstarts(record)

            record = BED.Record(b"chrXIII\t854794\t855293\tYMR292W\t0\t+\t854794\t855293\t0\t2\t22,395,\t0,104,")
            @test BED.chrom(record) == "chrXIII"
            @test BED.chromstart(record) === 854795
            @test BED.chromend(record) === 855293
            @test BED.name(record) == "YMR292W"
            @test BED.score(record) === 0
            @test BED.strand(record) === STRAND_POS
            @test BED.thickstart(record) === 854795
            @test BED.thickend(record) === 855293
            @test BED.itemrgb(record) === RGB(0, 0, 0)
            @test BED.blockcount(record) === 2
            @test BED.blocksizes(record) == [22, 395]
            @test BED.blockstarts(record) == [1, 105]

            record = BED.Record(b"chrX\t151080532\t151081699\tCHOCOLATE1\t0\t-\t151080532\t151081699\t255,127,36")
            @test BED.chrom(record) == "chrX"
            @test BED.chromstart(record) === 151080533
            @test BED.chromend(record) === 151081699
            @test BED.name(record) == "CHOCOLATE1"
            @test BED.score(record) === 0
            @test BED.strand(record) === STRAND_NEG
            @test BED.thickstart(record) === 151080533
            @test BED.thickend(record) === 151081699
            @test BED.itemrgb(record) === RGB(map(x -> reinterpret(N0f8, UInt8(x)), (255, 127, 36))...)
            @test !BED.hasblockcount(record)
            @test !BED.hasblocksizes(record)
            @test !BED.hasblockstarts(record)
        end

        get_bio_fmt_specimens()

        function check_bed_parse(filename)
            # Reading from a stream
            for interval in BED.Reader(open(filename))
            end

            # Reading from a regular file
            for interval in open(BED.Reader, filename)
            end

            # in-place parsing
            stream = open(BED.Reader, filename)
            entry = eltype(stream)()
            while !eof(stream)
                read!(stream, entry)
            end
            close(stream)

            # Check round trip
            output = IOBuffer()
            writer = BED.Writer(output)
            expected_entries = BED.Record[]
            for interval in open(BED.Reader, filename)
                write(writer, interval)
                push!(expected_entries, interval)
            end
            flush(writer)

            seekstart(output)
            read_entries = BED.Record[]
            for interval in BED.Reader(output)
                push!(read_entries, interval)
            end

            return expected_entries == read_entries
        end

        path = joinpath(dirname(@__FILE__), "..", "BioFmtSpecimens", "BED")
        for specimen in YAML.load_file(joinpath(path, "index.yml"))
            valid = get(specimen, "valid", true)
            if valid
                @test check_bed_parse(joinpath(path, specimen["filename"]))
            else
                @test_throws Exception check_bed_parse(joinpath(path, specimen["filename"]))
            end
        end
    end

    @testset "BED Intersection" begin
        # Testing strategy: there are two entirely separate intersection
        # algorithms for IntervalCollection and IntervalStream. Here we test
        # them both by checking that they agree by generating and intersecting
        # random BED files.

        function check_intersection(filename_a, filename_b)
            ic_a = IntervalCollection{BED.Record}()
            open(BED.Reader, filename_a) do reader
                for record in reader
                    push!(ic_a, Interval(record))
                end
            end

            ic_b = IntervalCollection{BED.Record}()
            open(BED.Reader, filename_b) do reader
                for record in reader
                    push!(ic_b, Interval(record))
                end
            end

            # This is refactored out to close streams
            fa = open(BED.Reader, filename_a)
            fb = open(BED.Reader, filename_b)
            xs = sort(collect(eachoverlap(fa, fb)))
            close(fa)
            close(fb)

            ys = sort(collect(eachoverlap(ic_a, ic_b)))

            return xs == ys
        end

        function write_intervals(filename, intervals)
            open(filename, "w") do out
                for interval in sort(intervals)
                    println(out, interval.seqname, "\t", interval.first - 1,
                            "\t", interval.last, "\t", interval.metadata, "\t",
                            1000, "\t", interval.strand)
                end
            end

        end

        n = 10000
        srand(1234)
        intervals_a = random_intervals(["one", "two", "three", "four", "five"],
                                       1000000, n)
        intervals_b = random_intervals(["one", "two", "three", "four", "five"],
                                       1000000, n)

        filename_a = "test_a.bed"
        filename_b = "test_b.bed"
        intempdir() do
            write_intervals(filename_a, intervals_a)
            write_intervals(filename_b, intervals_b)
            @test check_intersection(filename_a, filename_b)
        end

    end

    @testset "GFF3" begin
        record = GFF3.Record()
        @test !isfilled(record)

        record = GFF3.Record("CCDS1.1\tCCDS\tgene\t801943\t802434\t.\t-\t.\tNAME=LINC00115")
        @test isfilled(record)
        @test GFF3.isfeature(record)
        @test hasseqname(record)
        @test GFF3.hasseqid(record)
        @test seqname(record) == GFF3.seqid(record) == "CCDS1.1"
        @test GFF3.hassource(record)
        @test GFF3.source(record) == "CCDS"
        @test GFF3.hasfeaturetype(record)
        @test GFF3.featuretype(record) == "gene"
        @test GFF3.hasseqstart(record) === hasleftposition(record) === true
        @test GFF3.seqstart(record) === leftposition(record) === 801943
        @test GFF3.hasseqend(record) === hasrightposition(record) === true
        @test GFF3.seqend(record) === rightposition(record) === 802434
        @test !GFF3.hasscore(record)
        @test_throws MissingFieldException GFF3.score(record)
        @test GFF3.hasstrand(record)
        @test strand(record) === GFF3.strand(record) === STRAND_NEG
        @test !GFF3.hasphase(record)
        @test_throws MissingFieldException GFF3.phase(record)
        @test GFF3.attributes(record) == ["NAME" => ["LINC00115"]]
        @test GFF3.content(record) == "CCDS1.1\tCCDS\tgene\t801943\t802434\t.\t-\t.\tNAME=LINC00115"

        record = GFF3.Record("##gff-version 3")
        @test isfilled(record)
        @test GFF3.isdirective(record)
        @test GFF3.content(record) == "gff-version 3"
        @test convert(String, record) == "##gff-version 3"

        record = GFF3.Record("#comment")
        @test isfilled(record)
        @test GFF3.iscomment(record)
        @test GFF3.content(record) == "comment"
        @test convert(String, record) == "#comment"
    end

    @testset "GFF3 Parsing" begin
        get_bio_fmt_specimens()
        function check_gff3_parse(filename)
            # Reading from a stream
            num_intervals = 0
            for interval in GFF3.Reader(open(filename))
                num_intervals += 1
            end

            # Reading from a regular file
            for interval in open(GFF3.Reader, filename)
            end

            collection = IntervalCollection(open(GFF3.Reader, filename))
            @test length(collection) == num_intervals

            # in-place parsing
            stream = open(GFF3.Reader, filename)
            entry = eltype(stream)()
            while !eof(stream)
                try
                    read!(stream, entry)
                catch ex
                    if isa(ex, EOFError)
                        break
                    end
                end
            end
            close(stream)

            # copy
            records = GFF3.Record[]
            reader = open(GFF3.Reader, filename)
            output = IOBuffer()
            writer = GFF3.Writer(output)
            for record in reader
                write(writer, record)
                push!(records, record)
            end
            close(reader)
            flush(writer)

            records2 = GFF3.Record[]
            for record in GFF3.Reader(IOBuffer(takebuf_array(output)))
                push!(records2, record)
            end
            return records == records2
        end

        path = joinpath(dirname(@__FILE__), "..", "BioFmtSpecimens", "GFF3")
        for specimen in YAML.load_file(joinpath(path, "index.yml"))
            valid = get(specimen, "valid", true)
            if valid
                @test check_gff3_parse(joinpath(path, specimen["filename"]))
            else
                @test_throws Exception check_gff3_parse(joinpath(path, specimen["filename"]))
            end
        end

        # no fasta
        test_input = """
1	havana	exon	870086	870201	.	-	.	Parent=transcript:ENST00000432963;Name=ENSE00001791782;constitutive=0;ensembl_end_phase=-1;ensembl_phase=-1;exon_id=ENSE00001791782;rank=1;version=1
1	havana	lincRNA	868403	876802	.	-	.	ID=transcript:ENST00000427857;Parent=gene:ENSG00000230368;Name=FAM41C-002;biotype=lincRNA;havana_transcript=OTTHUMT00000007022;havana_version=1;transcript_id=ENST00000427857;transcript_support_level=3;version=1
"""
        stream = GFF3.Reader(IOBuffer(test_input))
        collect(stream)
        @test !GFF3.hasfasta(stream)
        @test_throws Exception GFF3.getfasta(stream)


        # implicit fasta
        test_input2 = string(test_input, """
>seq1
ACGTACGT
>seq2
TGCATGCA
""")
        stream = GFF3.Reader(IOBuffer(test_input2))
        collect(stream)
        @test GFF3.hasfasta(stream)
        @test collect(GFF3.getfasta(stream)) ==
            [FASTA.Record("seq1", dna"ACGTACGT")
             FASTA.Record("seq2", dna"TGCATGCA")]

        # explicit fasta
        test_input3 = string(test_input, """
##FASTA
>seq1
ACGTACGT
>seq2
TGCATGCA
""")
        stream = GFF3.Reader(IOBuffer(test_input3))
        collect(stream)
        @test GFF3.hasfasta(stream)
        @test collect(GFF3.getfasta(stream)) ==
            [FASTA.Record("seq1", dna"ACGTACGT")
             FASTA.Record("seq2", dna"TGCATGCA")]


        test_input4 = """
##directive1
#comment1
##directive2
1	havana	exon	869528	869575	.	-	.	Parent=transcript:ENST00000432963;Name=ENSE00001605362;constitutive=0;ensembl_end_phase=-1;ensembl_phase=-1;exon_id=ENSE00001605362;rank=2;version=1
1	havana	exon	870086	870201	.	-	.	Parent=transcript:ENST00000432963;Name=ENSE00001791782;constitutive=0;ensembl_end_phase=-1;ensembl_phase=-1;exon_id=ENSE00001791782;rank=1;version=1
##directive3
#comment2
##directive4
1	havana	lincRNA	868403	876802	.	-	.	ID=transcript:ENST00000427857;Parent=gene:ENSG00000230368;Name=FAM41C-002;biotype=lincRNA;havana_transcript=OTTHUMT00000007022;havana_version=1;transcript_id=ENST00000427857;transcript_support_level=3;version=1
##directive5
#comment3
##directive6
"""
        stream = GFF3.Reader(IOBuffer(test_input4), save_directives=true)
        read(stream)
        @test GFF3.directives(stream) == ["directive1", "directive2"]
        read(stream)
        @test isempty(GFF3.directives(stream))
        read(stream)
        @test GFF3.directives(stream) == ["directive3", "directive4"]
        @test_throws EOFError read(stream)
        @test eof(stream)
        close(stream)
        @test GFF3.directives(stream) == ["directive5", "directive6"]

        test_input5 = """
        ##directive1
        feature1\t.\t.\t.\t.\t.\t.\t.\t
        #comment1
        feature2\t.\t.\t.\t.\t.\t.\t.\t
        ##directive2
        feature3\t.\t.\t.\t.\t.\t.\t.\t
        """
        @test [r.kind for r in GFF3.Reader(IOBuffer(test_input5))] == [:feature, :feature, :feature]
        @test [r.kind for r in GFF3.Reader(IOBuffer(test_input5), skip_directives=false)] == [:directive, :feature, :feature, :directive, :feature]
        @test [r.kind for r in GFF3.Reader(IOBuffer(test_input5), skip_directives=false, skip_comments=false)] == [:directive, :feature, :comment, :feature, :directive, :feature]
    end
end


@testset "BigWig" begin
    @testset "empty" begin
        buffer = IOBuffer()
        data = buffer.data
        writer = BigWig.Writer(buffer, [("chr1", 1000)])
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        @test length(collect(reader)) == 0
    end

    @testset "small" begin
        buffer = IOBuffer()
        data = buffer.data
        writer = BigWig.Writer(buffer, [("chr1", 1000)])
        write(writer, ("chr1", 50, 100, 3.14))
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 1
        @test BigWig.haschrom(records[1]) === hasseqname(records[1]) === true
        @test BigWig.chrom(records[1]) == seqname(records[1]) == "chr1"
        @test BigWig.haschromstart(records[1]) === hasleftposition(records[1]) === true
        @test BigWig.chromstart(records[1]) === leftposition(records[1]) === 50
        @test BigWig.haschromend(records[1]) === hasrightposition(records[1]) === true
        @test BigWig.chromend(records[1]) === rightposition(records[1]) === 100
        @test BigWig.hasvalue(records[1])
        @test BigWig.value(records[1]) === 3.14f0
        @test startswith(repr(records[1]), "Bio.Intervals.BigWig.Record:\n")
        interval = convert(Interval, records[1])
        @test seqname(interval) == "chr1"
        @test leftposition(interval) === 50
        @test rightposition(interval) === 100
        @test metadata(interval) === 3.14f0
        @test all(isnan(BigWig.values(reader, "chr1", 1:49)))
        @test BigWig.values(reader, "chr1", 50:51) == [3.14f0, 3.14f0]
        @test BigWig.values(reader, "chr1", 99:100) == [3.14f0, 3.14f0]
        @test all(isnan(BigWig.values(reader, "chr1", 101:200)))
        @test BigWig.values(reader, Interval("chr1", 55, 56)) == [3.14f0, 3.14f0]

        # bedgraph (default)
        buffer = IOBuffer()
        data = buffer.data
        writer = BigWig.Writer(buffer, [("chr1", 1000)]; datatype=:bedgraph)
        write(writer, ("chr1",  1, 10, 0.0))
        write(writer, ("chr1", 15, 15, 1.0))
        write(writer, ("chr1", 90, 99, 2.0))
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 3
        @test BigWig.chrom.(records) == ["chr1", "chr1", "chr1"]
        @test BigWig.chromstart.(records) == [1, 15, 90]
        @test BigWig.chromend.(records) == [10, 15, 99]
        @test BigWig.value.(records) == [0.0, 1.0, 2.0]

        # varstep
        buffer = IOBuffer()
        data = buffer.data
        writer = BigWig.Writer(buffer, [("chr1", 1000)]; datatype=:varstep)
        write(writer, ("chr1",  1, 10, 0.0))
        write(writer, ("chr1", 15, 24, 1.0))
        write(writer, ("chr1", 90, 99, 2.0))
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 3
        @test BigWig.chrom.(records) == ["chr1", "chr1", "chr1"]
        @test BigWig.chromstart.(records) == [1, 15, 90]
        @test BigWig.chromend.(records) == [10, 24, 99]
        @test BigWig.value.(records) == [0.0, 1.0, 2.0]

        # fixedstep
        buffer = IOBuffer()
        data = buffer.data
        writer = BigWig.Writer(buffer, [("chr1", 1000)]; datatype=:fixedstep)
        write(writer, ("chr1",  1,  5, 0.0))
        write(writer, ("chr1", 11, 15, 1.0))
        write(writer, ("chr1", 21, 25, 2.0))
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 3
        @test BigWig.chrom.(records) == ["chr1", "chr1", "chr1"]
        @test BigWig.chromstart.(records) == [1, 11, 21]
        @test BigWig.chromend.(records) == [5, 15, 25]
        @test BigWig.value.(records) == [0.0, 1.0, 2.0]
    end

    @testset "large" begin
        buffer = IOBuffer()
        data = buffer.data
        binsize = 32
        writer = BigWig.Writer(buffer, [("chr1", 100_000), ("chr2", 90_000)], binsize=binsize)
        for i in 1:10_000
            write(writer, ("chr1", (i-1)*10+1, i*10, log(i)))
        end
        n = 0
        p = 1
        while p ≤ 90_000
            sz = min(rand(1:100), 90_000 - p)
            write(writer, ("chr2", p, p+sz, log(p)))
            n += 1
            p += sz + 1
        end
        close(writer)
        reader = BigWig.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 10_000 + n
        records = collect(eachoverlap(reader, Interval("chr1", 50_001, 50_165)))
        @test length(records) == 17
        @testset for bin in [1, 5, 10, 51, 300]
            for scale in 1:2
                binsize_scaled = binsize * BigWig.ZOOM_SCALE_FACTOR^(scale-1)
                chromstart = (bin - 1) * binsize_scaled + 1
                chromend = bin * binsize_scaled
                @test BigWig.coverage(reader, "chr1", chromstart, chromend; usezoom=false) == BigWig.coverage(reader, "chr1", chromstart, chromend; usezoom=true)
                @test_approx_eq BigWig.mean(reader, "chr1", chromstart, chromend; usezoom=false)    BigWig.mean(reader, "chr1", chromstart, chromend; usezoom=true)
                @test_approx_eq BigWig.minimum(reader, "chr1", chromstart, chromend; usezoom=false) BigWig.minimum(reader, "chr1", chromstart, chromend; usezoom=true)
                @test_approx_eq BigWig.maximum(reader, "chr1", chromstart, chromend; usezoom=false) BigWig.maximum(reader, "chr1", chromstart, chromend; usezoom=true)
                # TODO: use more stable algorithm?
                #@test_approx_eq BigWig.std(reader, "chr1", chromstart, chromend; usezoom=false)     BigWig.std(reader, "chr1", chromstart, chromend; usezoom=true)
            end
        end
    end

    @testset "round trip" begin
        function test_round_trip(filepath)
            reader = open(BigWig.Reader, filepath)
            buffer = IOBuffer()
            data = buffer.data
            writer = BigWig.Writer(buffer, BigWig.chromlist(reader))
            original = []
            for record in reader
                t = (BigWig.chrom(record), BigWig.chromstart(record), BigWig.chromend(record), BigWig.value(record))
                write(writer, t)
                push!(original, t)
            end
            close(writer)
            close(reader)

            reader = BigWig.Reader(IOBuffer(data))
            copy = []
            for record in reader
                t = (BigWig.chrom(record), BigWig.chromstart(record), BigWig.chromend(record), BigWig.value(record))
                push!(copy, t)
            end
            close(reader)

            @test original == copy
        end

        dir = joinpath(dirname(@__FILE__), "..", "BioFmtSpecimens", "BBI")
        for specimen in YAML.load_file(joinpath(dir, "index.yml"))
            valid = get(specimen, "valid", true)
            bigwig = "bigwig" ∈ split(specimen["tags"])
            if valid && bigwig
                test_round_trip(joinpath(dir, specimen["filename"]))
            end
        end
    end
end

@testset "BigBed" begin
    @testset "empty" begin
        buffer = IOBuffer()
        data = buffer.data
        writer = BigBed.Writer(buffer, [("chr1", 1000)])
        close(writer)
        reader = BigBed.Reader(IOBuffer(data))
        @test length(collect(reader)) == 0
    end

    @testset "small" begin
        buffer = IOBuffer()
        data = buffer.data
        writer = BigBed.Writer(buffer, [("chr1", 1000)])
        write(writer, ("chr1", 50, 100, "name1"))
        close(writer)
        reader = BigBed.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 1
        @test BigBed.chrom(records[1]) == "chr1"
        @test BigBed.chromstart(records[1]) === 50
        @test BigBed.chromend(records[1]) === 100
        @test BigBed.name(records[1]) == "name1"
        @test !BigBed.hasscore(records[1])
        @test BigBed.optionals(records[1]) == ["name1"]

        buffer = IOBuffer()
        data = buffer.data
        writer = BigBed.Writer(buffer, [("chr1", 1000)])
        write(writer, ("chr1", 1, 100, "some name", 100, '+', 10, 90, RGB(0.5, 0.1, 0.2), 2, [4, 10], [10, 20]))
        close(writer)
        reader = BigBed.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 1
        @test BigBed.haschrom(records[1]) === hasseqname(records[1]) === true
        @test BigBed.chrom(records[1]) == seqname(records[1]) == "chr1"
        @test BigBed.haschromstart(records[1]) === hasleftposition(records[1]) === true
        @test BigBed.chromstart(records[1]) === leftposition(records[1]) === 1
        @test BigBed.haschromend(records[1]) === hasrightposition(records[1]) === true
        @test BigBed.chromend(records[1]) === rightposition(records[1]) === 100
        @test BigBed.hasname(records[1])
        @test BigBed.name(records[1]) == "some name"
        @test BigBed.hasscore(records[1])
        @test BigBed.score(records[1]) === 100
        @test BigBed.hasstrand(records[1])
        @test BigBed.strand(records[1]) === STRAND_POS
        @test BigBed.hasthickstart(records[1])
        @test BigBed.thickstart(records[1]) === 10
        @test BigBed.hasthickend(records[1])
        @test BigBed.thickend(records[1]) === 90
        @test BigBed.hasitemrgb(records[1])
        @test BigBed.itemrgb(records[1]) === convert(RGB{N0f8}, RGB(0.5, 0.1, 0.2))
        @test BigBed.hasblockcount(records[1])
        @test BigBed.blockcount(records[1]) === 2
        @test BigBed.hasblocksizes(records[1])
        @test BigBed.blocksizes(records[1]) == [4, 10]
        @test BigBed.hasblockstarts(records[1])
        @test BigBed.blockstarts(records[1]) == [10, 20]
        @test BigBed.optionals(records[1]) == ["some name", "100", "+", "9", "90", "128,26,51", "2", "4,10,", "9,19,"]
    end

    @testset "large" begin
        buffer = IOBuffer()
        data = buffer.data
        binsize = 32
        writer = BigBed.Writer(buffer, [("chr1", 100_000), ("chr2", 90_000)], binsize=binsize)
        for i in 1:10_000
            write(writer, ("chr1", (i-1)*10+1, i*10, string("name", i)))
        end
        n = 0
        p = 1
        while p ≤ 90_000
            sz = min(rand(1:100), 90_000 - p)
            write(writer, ("chr2", p, p+sz, string("name", n + 1)))
            n += 1
            p += sz + 1
        end
        close(writer)
        reader = BigBed.Reader(IOBuffer(data))
        records = collect(reader)
        @test length(records) == 10_000 + n
        records = collect(eachoverlap(reader, Interval("chr1", 50_001, 50_165)))
        @test length(records) == 17
    end

    @testset "round trip" begin
        function test_round_trip(filepath)
            reader = open(BigBed.Reader, filepath)
            buffer = IOBuffer()
            data = buffer.data
            writer = BigBed.Writer(buffer, BigBed.chromlist(reader))
            original = []
            for record in reader
                t = (BigBed.chrom(record), BigBed.chromstart(record), BigBed.chromend(record), BigBed.optionals(record)...)
                write(writer, t)
                push!(original, t)
            end
            close(writer)
            close(reader)

            reader = BigBed.Reader(IOBuffer(data))
            copy = []
            for record in reader
                t = (BigBed.chrom(record), BigBed.chromstart(record), BigBed.chromend(record), BigBed.optionals(record)...)
                push!(copy, t)
            end
            close(reader)

            @test original == copy
        end

        dir = joinpath(dirname(@__FILE__), "..", "BioFmtSpecimens", "BBI")
        for specimen in YAML.load_file(joinpath(dir, "index.yml"))
            valid = get(specimen, "valid", true)
            bigbed = "bigbed" ∈ split(specimen["tags"])
            if valid && bigbed
                test_round_trip(joinpath(dir, specimen["filename"]))
            end
        end
    end

    @testset "overlap" begin
        chromlen = 1_000_000
        srand(1234)
        chroms = ["one", "two", "three", "four", "five"]
        intervals = IntervalCollection(
             [Interval(i.seqname, i.first, i.last)
             for i in random_intervals(chroms, chromlen, 10_000)], true)

        buffer = IOBuffer()
        data = buffer.data
        writer = BigBed.Writer(buffer, [(chrom, chromlen) for chrom in chroms])
        for i in intervals
            write(writer, i)
        end
        close(writer)

        reader = BigBed.Reader(IOBuffer(data))
        queries = random_intervals(chroms, chromlen, 1000)
        triplet(x::Interval) = String(x.seqname), x.first, x.last
        triplet(x::BigBed.Record) = BigBed.chrom(x), BigBed.chromstart(x), BigBed.chromend(x)
        @test all(triplet.(collect(eachoverlap(intervals, q))) == triplet.(collect(eachoverlap(reader, q))) for q in queries)
        close(reader)
    end
end

end # module TestIntervals
