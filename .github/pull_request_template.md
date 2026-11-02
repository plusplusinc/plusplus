<!-- Merges are squashed: this body becomes the commit message on main. Readable in a minute:
one or two plain sentences on what someone notices and why, then "What changes" as short
bullets (or a today-against-this-PR table), the before and after, and "How" for reviewers.
The pr skill has the shape; #138 is the model. Review notes and long measurements go in a
comment.
It is read before the merge, too: keep today and the change apart ("With this change, ..."),
never the result in the plain present.

The retro runs in a session that never saw this work and reads the conversation's text, not
what was run, so the body has to carry what it needs: the Card, Verified, and Friction lines, and any decision
the diff does not explain. A change someone can see shows its before and after here, as images
from scripts/pr-media.sh, never as a path to a local file. -->

<!-- One or two plain sentences: what someone notices, and why. -->

Card: <!-- the board card this PR came from, as [title](link from `scripts/board.sh show`); "Closes #N" when it was published as an issue; or "none" and why -->

## What changes

<!-- Short bullets, or a table of today against this PR. Then the before and after, and "How"
for reviewers, as the pr skill says. -->

Verified: <!-- exactly what was run: lint, which test tier, which screenshots were looked at -->

Friction: <!-- what was retried, what was corrected and who found it (the maintainer, an agent
review, the verifier, CI), what took longer than it should have, what was tried and abandoned.
"none" is a valid answer. -->
