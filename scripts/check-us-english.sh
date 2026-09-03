#!/bin/sh
# Fails when British spellings appear in source or documentation.
#
# With no arguments, checks every tracked text file. Given paths, checks only
# those, which is how the editor hook calls it.
#
# The list is explicit rather than clever. A blanket "-ise -> -ize" rule would
# flag advertise, exercise, supervise, compromise and surprise; a "-our -> -or"
# rule would flag four, hour, pour and your.
#
# Deliberately absent:
#   cancelled  - Swift's own `Task.isCancelled`, and Apple's docs use it in prose
#   dialogue   - a real US word, distinct from a UI "dialog"
#   towards    - standard in US English alongside "toward"
set -eu

SELF="scripts/check-us-english.sh"

WORDLIST='
colour:color
colours:colors
coloured:colored
colourful:colorful
behaviour:behavior
behaviours:behaviors
centre:center
centres:centers
centred:centered
centring:centering
honour:honor
honours:honors
honoured:honored
honouring:honoring
favour:favor
favours:favors
favourite:favorite
neighbour:neighbor
neighbours:neighbors
labour:labor
flavour:flavor
humour:humor
armour:armor
rumour:rumor
vapour:vapor
endeavour:endeavor
harbour:harbor
organise:organize
organised:organized
organising:organizing
organisation:organization
recognise:recognize
recognised:recognized
recognising:recognizing
normalise:normalize
normalised:normalized
normalising:normalizing
initialise:initialize
initialised:initialized
initialising:initializing
serialise:serialize
serialised:serialized
optimise:optimize
optimised:optimized
optimising:optimizing
prioritise:prioritize
prioritised:prioritized
customise:customize
customised:customized
minimise:minimize
maximise:maximize
emphasise:emphasize
emphasised:emphasized
summarise:summarize
summarised:summarized
utilise:utilize
realise:realize
realised:realized
specialise:specialize
standardise:standardize
synchronise:synchronize
synchronised:synchronized
visualise:visualize
categorise:categorize
categorised:categorized
analyse:analyze
analysed:analyzed
analysing:analyzing
paralyse:paralyze
licence:license
defence:defense
offence:offense
pretence:pretense
practise:practice
grey:gray
travelling:traveling
travelled:traveled
traveller:traveler
modelling:modeling
modelled:modeled
labelling:labeling
labelled:labeled
signalling:signaling
signalled:signaled
levelled:leveled
fuelled:fueled
catalogue:catalog
catalogues:catalogs
programme:program
metre:meter
metres:meters
litre:liter
fibre:fiber
sceptical:skeptical
judgement:judgment
whilst:while
amongst:among
learnt:learned
spelt:spelled
enquire:inquire
manoeuvre:maneuver
storey:story
tyre:tire
kerb:curb
cheque:check
aluminium:aluminum
mould:mold
draught:draft
artefact:artifact
artefacts:artifacts
rasterisation:rasterization
synthesise:synthesize
'

# One grep with every British form as an alternation; the wordlist is consulted only for
# the (rare) hits, to print the American form.
pattern=$(printf '%s\n' $WORDLIST | cut -d: -f1 | paste -sd '|' -)
if [ "$#" -eq 0 ]; then
    hits=$(git grep -nIwioE -- "$pattern" ':!'"$SELF" || true)
else
    hits=$(grep -HnIwioE -e "$pattern" "$@" 2> /dev/null || true)
fi

[ -z "$hits" ] && exit 0

printf '%s\n' "$hits" | while IFS=: read -r file line word; do
    lower=$(printf '%s' "$word" | tr '[:upper:]' '[:lower:]')
    american=$(printf '%s\n' $WORDLIST | grep "^$lower:" | cut -d: -f2)
    printf '%s:%s: use "%s" instead of "%s"\n' "$file" "$line" "$american" "$word"
done
echo ""
echo "This codebase writes US English. Fix the spellings above."
exit 1
