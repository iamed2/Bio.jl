# The Bio.Var module
# ==================
#
# Types and methods for analysing biological variation.
#
# Part of the Bio.Var module.
#
# This file is a part of BioJulia. License is MIT: https://github.com/BioJulia/Bio.jl/blob/master/LICENSE.md

module Var

import BioSymbols: ispurine, ispyrimidine
import Bio.Seq:
    Alphabet,
    DNAAlphabet,
    RNAAlphabet,
    BioSequence,
    MinHashSketch,
    Certain,
    Mismatch,
    Match
import Twiddle:
    enumerate_nibbles,
    nibble_mask,
    count_zero_nibbles,
    count_nonzero_nibbles,
    count_one_nibbles,
    count_zero_bitpairs,
    count_nonzero_bitpairs
import PairwiseListMatrices: PairwiseListMatrix
import Bio.Exceptions: MissingFieldException, missingerror
import Bio.Windows: eachwindow, EachWindowIterator, SeqWinItr
import Automa
import Automa.RegExp: @re_str
import BGZFStreams: BGZFStream
# TODO: Needs this branch: https://github.com/BioJulia/BufferedStreams.jl/pull/33
import BufferedStreams: BufferedStreams, BufferedInputStream
import IntervalTrees: Interval, IntervalValue
importall Bio

export
    # Site types
    Conserved,
    Mutated,
    Transition,
    Transversion,

    # VCF and BCF
    VCF,
    BCF,
    header,
    metainfotag,
    metainfoval,
    isfilled,

    MissingFieldException,
    mashdistance,
    distance,
    Proportion

# Bio.@reexport import Bio: isfilled, leftposition

include("site_counting/site_types/site_types.jl")
include("distances/dist.jl")
include("vcf/vcf.jl")
include("bcf/bcf.jl")
include("mash.jl")

end # module Var
